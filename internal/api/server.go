// Package api wires routes and HTTP handlers to the store/service layers.
package api

import (
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"

	"foodpos/backend/internal/auth"
	"foodpos/backend/internal/config"
	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/middleware"
	"foodpos/backend/internal/store"
	"foodpos/backend/internal/ws"
)

type Server struct {
	Store     *store.Store
	Auth      *auth.Manager
	Hub       *ws.Hub
	Tickets   *auth.TicketStore
	Cfg       config.Config
	UploadDir string // where menu photos are stored; served at /media/*
}

func (s *Server) Routes() http.Handler {
	r := chi.NewRouter()

	r.Use(chimw.RequestID)
	r.Use(chimw.Recoverer)
	r.Use(chimw.Logger)

	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		httpx.JSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	// Public static media (menu photos) — loaded by <img> tags without auth.
	if s.UploadDir != "" {
		r.Handle("/media/*", http.StripPrefix("/media/", http.FileServer(http.Dir(s.UploadDir))))
	}

	// Public (auth routes are rate-limited per IP; staff profiles are public
	// so terminals can render the PIN login screen before authentication).
	authLimit := middleware.RateLimit(20, time.Minute)
	registerLimit := middleware.RateLimit(10, time.Minute)
	deviceLimit := middleware.RateLimit(60, time.Minute)

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

	// Legacy terminal bootstrap (org_code optional; defaults to the demo org).
	r.Get("/api/v1/outlets", s.handleListOutlets)
	r.Get("/api/v1/staff", s.handleListStaff)
	r.Get("/api/v1/ws", s.Hub.Handler())

	// Owner account APIs (scope: owner).
	r.Route("/api/v1/saas", func(r chi.Router) {
		r.Use(middleware.Auth(s.Auth))
		r.Use(middleware.RequireScope(auth.ScopeOwner))
		r.Get("/me", s.handleSaaSMe)
		r.Get("/org", s.handleSaaSOrg)
		r.Post("/outlets", s.handleSaaSCreateOutlet)
		r.Post("/staff", s.handleSaaSCreateStaff)
		r.Post("/subscription/cancel", s.handleSaaSCancelSubscription)
		r.Post("/org/rotate-code", s.handleRotateOrgCode)
		r.Get("/invoices/{id}/pdf", s.handleOwnerInvoicePDF)
	})

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
		r.Get("/purchases", s.handleListPurchases)
		r.Get("/settings", s.handleGetSettings)

		// ---- Writes & back-office — kitchen is denied; paid writes gated ----
		r.Group(func(r chi.Router) {
			r.Use(s.entitlementGate())
			r.Use(middleware.DenyRoles("kitchen"))
			r.Use(s.auditMiddleware())

			r.Post("/auth/verify-manager-pin", s.handleVerifyManagerPin)

			// Staff (admin/manager)
			r.With(middleware.RequireRole("manager")).Post("/staff", s.handleCreateStaff)
			r.With(middleware.RequireRole("manager")).Patch("/staff/{id}", s.handlePatchStaff)

			// Tables
			r.Post("/tables", s.handleCreateTable)
			r.Patch("/tables/{id}", s.handlePatchTable)
			r.Post("/tables/{id}/move", s.handleMoveTable)
			r.Post("/tables/{id}/merge", s.handleMergeTable)
			r.Post("/tables/{id}/unmerge", s.handleUnmergeTable)

			// Menu
			r.With(middleware.RequireRole("manager")).Post("/menu", s.handleCreateMenuItem)
			r.With(middleware.RequireRole("manager")).Patch("/menu/{id}", s.handlePatchMenuItem)
			r.With(middleware.RequireRole("manager")).Delete("/menu/{id}", s.handleDeleteMenuItem)
			r.With(middleware.RequireRole("manager")).Post("/uploads/menu-image", s.handleUploadMenuImage)

			// Orders
			r.Post("/orders", s.handleCreateOrder)
			r.Patch("/orders/{id}", s.handlePatchOrder)
			r.Post("/orders/{id}/items", s.handleAddOrderItem)
			r.Patch("/orders/{id}/items/{itemId}", s.handlePatchOrderItem)
			r.Post("/orders/{id}/items/{itemId}/cancel", s.handleCancelOrderItem)
			r.Post("/orders/{id}/kot", s.handleFireKOT)
			r.Post("/orders/{id}/pay", s.handlePay)
			r.Post("/orders/{id}/refund", s.handleRefund)

			// Shifts & cash
			r.Post("/shifts/open", s.handleOpenShift)
			r.Post("/shifts/current/close", s.handleCloseShift)
			r.Post("/shifts/current/cash-move", s.handleCashMove)

			// Expenses / Customers
			r.Post("/expenses", s.handleCreateExpense)
			r.Delete("/expenses/{id}", s.handleDeleteExpense)
			r.Post("/customers", s.handleCreateCustomer)
			r.Post("/customers/{id}/credit", s.handleBookCredit)

			// Inventory / suppliers / purchases
			r.With(middleware.RequireRole("manager")).Post("/inventory", s.handleCreateInventoryItem)
			r.Post("/inventory/{id}/adjust", s.handleAdjustStock)
			r.Post("/suppliers", s.handleCreateSupplier)
			r.Post("/purchases", s.handleCreatePurchase)
			r.Patch("/purchases/{id}", s.handlePatchPurchase)

			// Settings & reports
			r.With(middleware.RequireRole("manager")).Put("/settings", s.handlePutSettings)
			// Overall revenue dashboard is Admin-only; the shift Z-report
			// stays reachable by manager/cashier for close-shift.
			r.With(middleware.RequireRole("admin")).Get("/reports/dashboard", s.handleDashboardReport)
			r.Get("/reports/shift/{id}/zreport", s.handleZReport)
		})
	})

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
