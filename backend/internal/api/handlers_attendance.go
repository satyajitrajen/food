package api

// Staff attendance endpoints. Clock-in happens automatically on staff login
// (handleLogin); clock-out automatically on logout (handleLogout) — these
// endpoints exist as explicit escape hatches (shift handover without logout)
// and for the ledger read. Supplier payout endpoints live here too: the
// ledger read is staff-visible, the write is manager-only.

import (
	"net/http"

	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/middleware"
	"foodpos/backend/internal/models"
)

// handleClockIn opens (or idempotently returns) the signed-in staff's open
// attendance session for the current outlet.
func (s *Server) handleClockIn(w http.ResponseWriter, r *http.Request) {
	c, ok := middleware.ClaimsFrom(r.Context())
	if !ok {
		httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
		return
	}
	outletID := outletScope(r)
	if outletID == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_outlet", "outlet_id is required"))
		return
	}
	entry, err := s.Store.ClockInStaff(r.Context(), c.OrgID, outletID, c.ActorID, c.Name)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, entry)
}

// handleClockOut closes the caller's open attendance session (no-op when
// already closed).
func (s *Server) handleClockOut(w http.ResponseWriter, r *http.Request) {
	c, ok := middleware.ClaimsFrom(r.Context())
	if !ok {
		httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
		return
	}
	entry, err := s.Store.ClockOutStaff(r.Context(), c.ActorID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"closed": entry != nil})
}

// handleListAttendance serves the ledger. Managers/admins see the whole org
// (optionally filtered by ?staff_id=); every other role is hard-scoped to
// their own entries — never another staff member's.
func (s *Server) handleListAttendance(w http.ResponseWriter, r *http.Request) {
	c, ok := middleware.ClaimsFrom(r.Context())
	if !ok {
		httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
		return
	}
	staffID := r.URL.Query().Get("staff_id")
	switch c.Role {
	case "admin", "manager":
		// optional staff_id filter stays caller-controlled
	default:
		staffID = c.ActorID
	}
	entries, err := s.Store.ListAttendance(r.Context(), c.OrgID, staffID,
		r.URL.Query().Get("from"), r.URL.Query().Get("to"), queryInt(r, "limit", 200))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"attendance": entries})
}

// handleListSupplierPayments: payout ledger for one supplier (READS — visible
// to any signed-in staff of the outlet).
func (s *Server) handleListSupplierPayments(w http.ResponseWriter, r *http.Request) {
	outletID := outletScope(r)
	if outletID == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_outlet", "outlet_id is required"))
		return
	}
	payments, err := s.Store.ListSupplierPayments(r.Context(), outletID, pathID(r, "id"), queryInt(r, "limit", 200))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"payments": payments})
}

// handleCreateSupplierPayment: manager-only direct payout. Atomically reduces
// the supplier's outstanding due and returns the payment + updated supplier
// (server truth for the client ledger). The drawer leg for cash payouts stays
// the expense/cash-move flow's job (single source of truth for shift math).
func (s *Server) handleCreateSupplierPayment(w http.ResponseWriter, r *http.Request) {
	var req models.SupplierPaymentCreate
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	outletID := outletScope(r)
	if outletID == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_outlet", "outlet_id is required"))
		return
	}
	if sup, err := s.Store.GetSupplier(r.Context(), pathID(r, "id")); err != nil || sup == nil || sup.OutletID != outletID {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_supplier", "Supplier not found in this outlet"))
		return
	}
	claims, _ := claimsFrom(r)
	pay, sup, err := s.Store.CreateSupplierPayment(r.Context(), outletID, pathID(r, "id"), req, claims.ActorID, claims.Name)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, map[string]any{"payment": pay, "supplier": sup})
}

// handleListCashMoves: recent cash-move ledger across the outlet's shifts
// (manager audit view; mirrors the terminal ledger on hydration).
func (s *Server) handleListCashMoves(w http.ResponseWriter, r *http.Request) {
	outletID := outletScope(r)
	if outletID == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_outlet", "outlet_id is required"))
		return
	}
	moves, err := s.Store.ListCashTransactions(r.Context(), outletID, queryInt(r, "limit", 200))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"cash_moves": moves})
}
