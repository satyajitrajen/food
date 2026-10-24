// Package api wires routes and HTTP handlers to the store/service layers.
package api

import (
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"

	"foodpos/backend/internal/auth"
	"foodpos/backend/internal/config"
	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/middleware"
	"foodpos/backend/internal/notify"
	"foodpos/backend/internal/store"
	"foodpos/backend/internal/web"
	"foodpos/backend/internal/ws"
)

type Server struct {
	Store     *store.Store
	Auth      *auth.Manager
	Hub       *ws.Hub
	Tickets   *auth.TicketStore
	Cfg       config.Config
	UploadDir string // where menu photos are stored; served at /media/*
	Notifier  *notify.FCMNotifier

	pinOnce sync.Once
	pinLock *auth.PINLockout
}

func (s *Server) Routes() http.Handler {
	r := chi.NewRouter()

	r.Use(chimw.RequestID)
	r.Use(chimw.Recoverer)
	r.Use(chimw.Logger)
	r.Use(middleware.CORS(s.Cfg.CORSOrigins))

	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		httpx.JSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	// Public static media (menu photos) — loaded by <img> tags without auth.
	if s.UploadDir != "" {
		r.Handle("/media/*", http.StripPrefix("/media/", mediaHandler(s.UploadDir)))
	}

	// Public (auth routes are rate-limited per IP; staff profiles are public
	// so terminals can render the PIN login screen before authentication).
	authLimit := middleware.RateLimit(20, time.Minute)
	registerLimit := middleware.RateLimit(30, time.Minute)
	deviceLimit := middleware.RateLimit(60, time.Minute)
	pinLimit := middleware.RateLimit(30, time.Minute)

	r.With(authLimit).Post("/api/v1/auth/login", s.handleLogin)
	r.With(authLimit).Post("/api/v1/auth/refresh", s.handleRefresh)
	r.With(authLimit).Post("/api/v1/auth/logout", s.handleLogout)

	// SaaS self-registration + owner + platform admin auth.
	r.With(registerLimit).Post("/api/v1/auth/register", s.handleRegisterOrg)
	r.With(authLimit).Post("/api/v1/auth/account/login", s.handleAccountLogin)
	r.With(authLimit).Post("/api/v1/auth/account/refresh", s.handleAccountRefresh)
	r.With(authLimit).Post("/api/v1/auth/account/logout", s.handleAccountLogout)
	r.With(registerLimit).Post("/api/v1/auth/account/forgot", s.handleForgotPassword)
	r.With(registerLimit).Post("/api/v1/auth/account/reset", s.handleResetPassword)
	r.With(registerLimit).Post("/api/v1/auth/account/verify", s.handleVerifyEmail)
	r.With(authLimit).Post("/api/v1/admin/login", s.handleAdminLogin)
	r.With(authLimit).Post("/api/v1/admin/refresh", s.handleAdminRefresh)
	r.With(authLimit).Post("/api/v1/admin/logout", s.handleAdminLogout)
	r.With(deviceLimit).Post("/api/v1/auth/device-options", s.handleDeviceOptions)

	// Marketing lead capture from the landing page (public, rate-limited).
	r.With(registerLimit).Post("/api/v1/leads", s.handleCreateLead)

	// Customer digital menu (public): the page a table QR opens.
	r.Get("/m/{outletID}", s.handleCustomerMenu)

	// Pre-login terminal bootstrap (org_code required; minimal fields).
	r.With(deviceLimit).Get("/api/v1/outlets", s.handleListOutlets)
	r.With(deviceLimit).Get("/api/v1/staff", s.handleListStaff)
	// Realtime stream: single-use ticket from POST /ws/ticket only.
	r.Get("/api/v1/ws", s.Hub.Handler())

	// Owner account APIs (scope: owner).
	r.Route("/api/v1/saas", func(r chi.Router) {
		r.Use(middleware.Auth(s.Auth))
		r.Use(middleware.RequireScope(auth.ScopeOwner))
		r.Get("/me", s.handleSaaSMe)
		r.Get("/org", s.handleSaaSOrg)
		r.Post("/outlets", s.handleSaaSCreateOutlet)
		r.With(s.announce("staff")).Post("/staff", s.handleSaaSCreateStaff)
		r.Post("/subscription/cancel", s.handleSaaSCancelSubscription)
		r.Post("/subscription/razorpay", s.handleOwnerStartSubscription)
		r.Post("/subscription/manual-order", s.handleOwnerManualOrder)
		r.Post("/org/rotate-code", s.handleRotateOrgCode)
		r.Delete("/org", s.handleDeleteOrg)
		r.Get("/invoices/{id}/pdf", s.handleOwnerInvoicePDF)
	})

	// Staff-scoped subscription status for the POS app's Settings card.
	// Root-level static route: /api/v1/saas/* is claimed by the owner mount
	// above, so this cannot be registered inside the staff group. The full
	// staff chain is replicated explicitly. A pure read — deliberately NOT
	// behind the entitlement gate so an expired org can still see its status
	// and renew (the gate blocks by group membership, not HTTP method).
	r.With(middleware.Auth(s.Auth), middleware.RequireScope(auth.ScopeStaff),
		middleware.StaffTenant(), middleware.RequireRole("manager")).
		Get("/api/v1/saas/subscription/status", s.handleSubscriptionAppStatus)

	// Platform superadmin APIs (scope: admin).
	r.Route("/api/v1/admin", func(r chi.Router) {
		r.Use(middleware.Auth(s.Auth))
		r.Use(middleware.RequireScope(auth.ScopeAdmin))
		r.Get("/orgs", s.handleListAdminOrgs)
		r.Get("/orgs/{id}", s.handleAdminOrgDetail)
		r.Post("/orgs/{id}/activate", s.handleAdminActivate)
		r.Post("/orgs/{id}/extend", s.handleAdminExtend)
		r.Post("/orgs/{id}/suspend", s.handleAdminSuspend)
		r.Post("/orgs/{id}/cancel", s.handleAdminCancel)
		r.Post("/orgs/{id}/checkout", s.handleAdminCheckout)
		r.Get("/invoices/{id}/pdf", s.handleAdminInvoicePDF)
		r.Get("/leads", s.handleAdminListLeads)
		r.Get("/stats", s.handleAdminStats)
	})

	// Razorpay webhook (public; signature-verified).
	r.Post("/api/v1/webhooks/razorpay", s.handleRazorpayWebhook)

	// Authenticated POS routes (scope: staff, tenant-bound).
	r.Route("/api/v1", func(r chi.Router) {
		r.Use(middleware.Auth(s.Auth))
		r.Use(middleware.RequireScope(auth.ScopeStaff))
		r.Use(middleware.StaffTenant())

		// Kitchen display (role 'kitchen') is display-only. It may exchange
		// its JWT for an SSE ticket and read the KOT board + hydrate its
		// terminal; every write below is denied to it via DenyRoles.
		r.Post("/ws/ticket", s.handleWsTicket)
		r.Post("/devices/token", s.handleRegisterDeviceToken)
		r.Delete("/devices/token", s.handleUnregisterDeviceToken)
		r.Get("/outlets/{id}", s.handleGetOutlet)
		r.Get("/tables", s.handleListTables)
		r.Get("/menu", s.handleListMenu)
		r.Get("/menu/{id}", s.handleGetMenuItem)
		r.Get("/orders", s.handleListOrders)
		r.Get("/orders/{id}", s.handleGetOrder)
		r.Get("/kots", s.handleListKOTs)
		r.Patch("/kots/{id}", s.handlePatchKOT)
		r.Get("/shifts/current", s.handleCurrentShift)
		r.Get("/shifts", s.handleListShifts)
		r.Get("/expenses", s.handleListExpenses)
		r.Get("/customers", s.handleListCustomers)
		r.Get("/customers/{id}/credit-log", s.handleListCreditLog)
		r.Get("/inventory", s.handleListInventory)
		r.Get("/inventory/{id}/adjustments", s.handleListStockLog)
		r.Get("/inventory/adjustments", s.handleListStockLog)
		r.Get("/suppliers", s.handleListSuppliers)
		r.Get("/suppliers/{id}/payments", s.handleListSupplierPayments)
		r.Get("/purchases", s.handleListPurchases)
		r.Get("/cash-moves", s.handleListCashMoves)
		// Attendance: explicit clock hooks + ledger (server auto clocks in on
		// login / out on logout; these are escape hatches + the read).
		r.Post("/attendance/clock-in", s.handleClockIn)
		r.Post("/attendance/clock-out", s.handleClockOut)
		r.Get("/attendance", s.handleListAttendance)
		r.Get("/settings", s.handleGetSettings)

		// Self-service profile: every signed-in staff member, incl. kitchen.
		r.Get("/me", s.handleGetMe)
		r.Patch("/me", s.handlePatchMe)
		r.With(pinLimit).Post("/me/pin", s.handleChangeMyPIN)
		r.Post("/me/avatar", s.handleUploadMenuImage)

		// ---- Writes & back-office — kitchen is denied; paid writes gated ----
		r.Group(func(r chi.Router) {
			r.Use(s.entitlementGate())
			r.Use(middleware.DenyRoles("kitchen"))
			r.Use(s.auditMiddleware())

			manager := middleware.RequireRole("manager")
			// Money and drawer operations are cashier+ (waiters take orders only).
			noWaiter := middleware.DenyRoles("waiter")

			r.With(pinLimit).Post("/auth/verify-manager-pin", s.handleVerifyManagerPin)

			// Staff + outlet profile (admin/manager)
			r.With(manager, s.announce("staff")).Post("/staff", s.handleCreateStaff)
			r.With(manager, s.announce("staff")).Patch("/staff/{id}", s.handlePatchStaff)
			r.With(manager).Get("/staff/all", s.handleListAllStaff)
			r.With(manager).Patch("/outlets/{id}", s.handlePatchOutlet)

			// Tables
			r.With(manager).Post("/tables", s.handleCreateTable)
			r.Patch("/tables/{id}", s.handlePatchTable)
			r.With(manager).Delete("/tables/{id}", s.handleDeleteTable)
			r.Post("/tables/{id}/move", s.handleMoveTable)
			r.With(manager).Post("/tables/{id}/merge", s.handleMergeTable)
			r.With(manager).Post("/tables/{id}/unmerge", s.handleUnmergeTable)

			// Menu
			r.With(manager, s.announce("menu")).Post("/menu", s.handleCreateMenuItem)
			r.With(manager, s.announce("menu")).Patch("/menu/{id}", s.handlePatchMenuItem)
			r.With(manager, s.announce("menu")).Delete("/menu/{id}", s.handleDeleteMenuItem)
			r.With(manager).Post("/uploads/menu-image", s.handleUploadMenuImage)
			r.With(manager).Post("/uploads/image", s.handleUploadMenuImage)

			// Orders
			r.Post("/orders", s.handleCreateOrder)
			r.Patch("/orders/{id}", s.handlePatchOrder)
			r.Post("/orders/{id}/items", s.handleAddOrderItem)
			r.Patch("/orders/{id}/items/{itemId}", s.handlePatchOrderItem)
			r.Post("/orders/{id}/items/{itemId}/cancel", s.handleCancelOrderItem)
			r.Post("/orders/{id}/kot", s.handleFireKOT)
			r.Post("/orders/{id}/cancel", s.handleCancelOrder)
			r.With(noWaiter).Post("/orders/{id}/pay", s.handlePay)
			r.With(noWaiter).Post("/orders/{id}/refund", s.handleRefund)

			// Shifts & cash
			r.With(noWaiter).Post("/shifts/open", s.handleOpenShift)
			r.With(noWaiter).Post("/shifts/current/close", s.handleCloseShift)
			r.With(noWaiter).Post("/shifts/current/cash-move", s.handleCashMove)

			// Expenses / Customers
			r.With(noWaiter, s.announce("expense")).Post("/expenses", s.handleCreateExpense)
			r.With(manager, s.announce("expense")).Delete("/expenses/{id}", s.handleDeleteExpense)
			r.With(manager, s.announce("expense")).Patch("/expenses/{id}", s.handlePatchExpense)
			r.With(s.announce("customer")).Post("/customers", s.handleCreateCustomer)
			r.With(noWaiter).Patch("/customers/{id}", s.handlePatchCustomer)
			r.With(manager).Delete("/customers/{id}", s.handleDeleteCustomer)
			r.With(noWaiter, s.announce("customer")).Post("/customers/{id}/credit", s.handleBookCredit)

			// Inventory / suppliers / purchases (back office: manager+)
			r.With(manager, s.announce("inventory")).Post("/inventory", s.handleCreateInventoryItem)
			r.With(manager, s.announce("inventory")).Post("/inventory/{id}/adjust", s.handleAdjustStock)
			r.With(manager).Patch("/inventory/{id}", s.handlePatchInventoryItem)
			r.With(manager).Delete("/inventory/{id}", s.handleDeleteInventoryItem)
			r.With(manager, s.announce("supplier")).Post("/suppliers", s.handleCreateSupplier)
			r.With(manager).Patch("/suppliers/{id}", s.handlePatchSupplier)
			r.With(manager).Delete("/suppliers/{id}", s.handleDeleteSupplier)
			r.With(manager, s.announce("supplier")).Post("/suppliers/{id}/payments", s.handleCreateSupplierPayment)
			r.With(manager, s.announce("purchase")).Post("/purchases", s.handleCreatePurchase)
			r.With(manager, s.announce("purchase")).Patch("/purchases/{id}", s.handlePatchPurchase)

			// Settings & reports
			r.With(manager).Put("/settings", s.handlePutSettings)
			// Overall revenue dashboard is Admin-only; the shift Z-report
			// stays reachable by manager/cashier for close-shift.
			r.With(middleware.RequireRole("admin")).Get("/reports/dashboard", s.handleDashboardReport)
			r.Get("/reports/shift/{id}/zreport", s.handleZReport)
		})
	})

	// Embedded web app (landing + console) — catch-all, registered last so
	// every API/media/ws route above wins.
	r.Handle("/*", web.Handler())

	return r
}

func pathID(r *http.Request, name string) string { return chi.URLParam(r, name) }

// claimsFrom is a small wrapper used across handler files.
func claimsFrom(r *http.Request) (*auth.Claims, bool) {
	return middleware.ClaimsFrom(r.Context())
}

func queryInt(r *http.Request, name string, def int) int {
	v := r.URL.Query().Get(name)
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return def
	}
	return n
}
