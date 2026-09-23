package api

import (
	"context"
	"net/http"
	"time"

	"foodpos/backend/internal/auth"
	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/middleware"
	"foodpos/backend/internal/models"
)

type loginReq struct {
	StaffID  string `json:"staff_id"`
	PIN      string `json:"pin"`
	OutletID string `json:"outlet_id"`
}

type tokenResp struct {
	Token            string              `json:"token"`
	RefreshToken     string              `json:"refresh_token,omitempty"`
	TokenType        string              `json:"token_type"`
	ExpiresAt        time.Time           `json:"expires_at"`
	Staff            models.Staff        `json:"staff"`
	Entitlement      *models.Entitlement `json:"entitlement,omitempty"`
	EntitlementToken string              `json:"entitlement_token,omitempty"`
}

func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	var req loginReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if req.StaffID == "" || req.PIN == "" || req.OutletID == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_credentials", "staff_id, pin and outlet_id are required"))
		return
	}
	row, err := s.Store.GetStaff(r.Context(), req.StaffID)
	if err != nil || !row.IsActive || !s.Auth.CheckPIN(row.PINHash, req.PIN) {
		httpx.ErrorJSON(w, r, httpx.NewError(401, "bad_credentials", "Invalid staff or PIN"))
		return
	}
	// Tenant enforcement: the staff must belong to the outlet's org (outlet_id
	// NULL = org-wide staff such as managers/admins).
	outlet, err := s.Store.GetOutlet(r.Context(), req.OutletID)
	if err != nil || outlet.OrgID != row.OrgID {
		httpx.ErrorJSON(w, r, httpx.NewError(403, "forbidden_outlet", "Staff is not part of this outlet's organization"))
		return
	}
	if row.Role == "waiter" && (row.OutletID == nil || *row.OutletID == "") {
		httpx.ErrorJSON(w, r, httpx.NewError(403, "forbidden_outlet", "Waiter is not assigned to any outlet"))
		return
	}
	if row.Role == "kitchen" && (row.OutletID == nil || *row.OutletID == "") {
		httpx.ErrorJSON(w, r, httpx.NewError(403, "forbidden_outlet", "Kitchen staff is not assigned to any outlet"))
		return
	}
	if row.OutletID != nil && *row.OutletID != req.OutletID {
		httpx.ErrorJSON(w, r, httpx.NewError(403, "forbidden_outlet", "Staff is not assigned to this outlet"))
		return
	}
	token, err := s.Auth.IssueStaffToken(row.ID, row.Name, row.Role, row.OrgID, req.OutletID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	refresh, hash := auth.NewRefreshToken()
	if err := s.Store.CreateStaffSession(r.Context(), row.ID, row.OrgID, req.OutletID, hash,
		time.Now().Add(auth.RefreshTTL)); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	ent, _ := s.Store.GetEntitlement(r.Context(), row.OrgID)
	// Attendance: a fresh login opens (or idempotently reuses) the clock-in
	// session. Best-effort — never blocks the login.
	_, _ = s.Store.ClockInStaff(r.Context(), row.OrgID, req.OutletID, row.ID, row.Name)
	httpx.JSON(w, http.StatusOK, tokenResp{
		Token: token, RefreshToken: refresh, TokenType: "Bearer",
		ExpiresAt: time.Now().Add(auth.AccessTTL), Staff: row.Staff,
		Entitlement: ent, EntitlementToken: s.signedEntitlementToken(ent),
	})
}

type refreshReq struct {
	RefreshToken string `json:"refresh_token"`
}

// handleRefresh rotates a staff refresh session (generic auth_refresh table).
func (s *Server) handleRefresh(w http.ResponseWriter, r *http.Request) {
	var req refreshReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if req.RefreshToken == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_credentials", "refresh_token is required"))
		return
	}
	sess, err := s.Store.GetSession(r.Context(), auth.HashToken(req.RefreshToken))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if sess.Revoked || time.Now().After(sess.ExpiresAt) || sess.Scope != auth.ScopeStaff {
		httpx.ErrorJSON(w, r, httpx.NewError(401, "invalid_refresh_token", "Refresh token is expired or revoked"))
		return
	}
	row, err := s.Store.GetStaff(r.Context(), sess.ActorID)
	if err != nil || !row.IsActive {
		httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
		return
	}
	_ = s.Store.RevokeSession(r.Context(), sess.ID)
	token, err := s.Auth.IssueStaffToken(row.ID, row.Name, row.Role, sess.OrgID, sess.OutletID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	refresh, hash := auth.NewRefreshToken()
	if err := s.Store.CreateStaffSession(r.Context(), row.ID, sess.OrgID, sess.OutletID, hash,
		time.Now().Add(auth.RefreshTTL)); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	ent, _ := s.Store.GetEntitlement(r.Context(), sess.OrgID)
	httpx.JSON(w, http.StatusOK, tokenResp{
		Token: token, RefreshToken: refresh, TokenType: "Bearer",
		ExpiresAt: time.Now().Add(auth.AccessTTL), Staff: row.Staff,
		Entitlement: ent, EntitlementToken: s.signedEntitlementToken(ent),
	})
}

// handleLogout revokes a staff session (works for owner/admin bodies too —
// owner/admin logouts use their own handlers).
func (s *Server) handleLogout(w http.ResponseWriter, r *http.Request) {
	var req refreshReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if sess, err := s.Store.GetSession(r.Context(), auth.HashToken(req.RefreshToken)); err == nil {
		// Attendance: logout closes the staff member's open clock-in session.
		if sess.Scope == auth.ScopeStaff {
			_, _ = s.Store.ClockOutStaff(r.Context(), sess.ActorID)
		}
		_ = s.Store.RevokeSession(r.Context(), sess.ID)
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"revoked": true})
}

// handleWsTicket exchanges the authenticated JWT for a single-use, short-TTL
// connect ticket for GET /ws. Only staff tokens may open realtime streams.
func (s *Server) handleWsTicket(w http.ResponseWriter, r *http.Request) {
	if s.Tickets == nil {
		httpx.ErrorJSON(w, r, httpx.NewError(501, "tickets_disabled", "SSE tickets are not configured"))
		return
	}
	claims, ok := claimsFrom(r)
	if !ok || claims.Scope != auth.ScopeStaff || claims.OutletID == "" {
		httpx.ErrorJSON(w, r, httpx.ErrForbidden)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{
		"ticket":     s.Tickets.Issue(claims),
		"expires_at": time.Now().Add(auth.SSETicketTTL).UTC(),
	})
}

type managerPinReq struct {
	PIN string `json:"pin"`
}

type managerPinResp struct {
	Valid bool          `json:"valid"`
	Staff *models.Staff `json:"staff,omitempty"`
}

func (s *Server) handleVerifyManagerPin(w http.ResponseWriter, r *http.Request) {
	var req managerPinReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	valid, staff, err := s.checkManagerPIN(r.Context(), req.PIN)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, managerPinResp{Valid: valid, Staff: staff})
}

// checkManagerPIN matches a PIN against active manager/admin staff OF THE
// REQUESTER'S ORG (previously global — a cross-tenant escalation).
func (s *Server) checkManagerPIN(ctx context.Context, pin string) (bool, *models.Staff, error) {
	if pin == "" {
		return false, nil, nil
	}
	orgID := ""
	if c, ok := middleware.ClaimsFrom(ctx); ok {
		orgID = c.OrgID
	}
	staffList, err := s.Store.ListStaff(ctx, orgID, "")
	if err != nil {
		return false, nil, err
	}
	for _, st := range staffList {
		if st.Role != "manager" && st.Role != "admin" {
			continue
		}
		row, err := s.Store.GetStaff(ctx, st.ID)
		if err != nil {
			continue
		}
		if s.Auth.CheckPIN(row.PINHash, pin) {
			return true, &row.Staff, nil
		}
	}
	return false, nil, nil
}

// requireManagerPIN enforces FR-A3 server-side: privileged ops (discount above
// threshold, item cancellation after KOT, refunds) must carry a valid
// manager/admin PIN of the same org.
func (s *Server) requireManagerPIN(ctx context.Context, pin string) error {
	valid, _, err := s.checkManagerPIN(ctx, pin)
	if err != nil {
		return err
	}
	if !valid {
		if pin == "" {
			return httpx.NewError(403, "manager_pin_required",
				"This action requires manager authorization (manager_pin)")
		}
		return httpx.NewError(403, "invalid_manager_pin", "Invalid manager PIN")
	}
	return nil
}

// handleListStaff is a transitional public endpoint used by legacy terminals
// pre-login: org is resolved from ?org_code= (defaults to the demo org).
func (s *Server) handleListStaff(w http.ResponseWriter, r *http.Request) {
	orgID, err := s.orgFromCodeOrDemo(r)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	outletID := r.URL.Query().Get("outlet_id")
	list, err := s.Store.ListStaff(r.Context(), orgID, outletID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"staff": list})
}

func (s *Server) handleCreateStaff(w http.ResponseWriter, r *http.Request) {
	var req models.StaffCreate
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if len(req.PIN) < 4 || len(req.PIN) > 6 || !allDigits(req.PIN) {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_pin", "PIN must be 4-6 digits"))
		return
	}
	claims, ok := claimsFrom(r)
	if !ok {
		httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
		return
	}
	switch req.Role {
	case "admin", "manager", "cashier", "waiter", "kitchen":
	default:
		httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_role", "role must be admin, manager, cashier, waiter or kitchen"))
		return
	}
	// Managers cannot create admin staff (privilege escalation).
	if claims.Role == "manager" && req.Role == "admin" {
		httpx.ErrorJSON(w, r, httpx.NewError(403, "admin_only", "Only admins can create admin staff"))
		return
	}
	if req.Role == "waiter" || req.Role == "kitchen" {
		if req.OutletID == nil || *req.OutletID == "" {
			if outID := outletScope(r); outID != "" {
				req.OutletID = &outID
			} else {
				httpx.ErrorJSON(w, r, httpx.NewError(400, "outlet_required", "A waiter or kitchen staff must be assigned to a specific outlet"))
				return
			}
		}
	}
	if req.OutletID != nil && *req.OutletID != "" {
		out, err := s.Store.GetOutlet(r.Context(), *req.OutletID)
		if err != nil || out.OrgID != claims.OrgID {
			httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_outlet", "Outlet does not belong to this organization"))
			return
		}
	}
	if err := s.enforceStaffLimit(r, claims.OrgID); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	hash, err := s.Auth.HashPIN(req.PIN)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	st, err := s.Store.CreateStaff(r.Context(), claims.OrgID, req, hash)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, st)
}

func (s *Server) handlePatchStaff(w http.ResponseWriter, r *http.Request) {
	var p models.StaffPatch
	if err := httpx.Decode(r, &p); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if p.Role != nil {
		switch *p.Role {
		case "admin", "manager", "cashier", "waiter", "kitchen":
		default:
			httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_role", "role must be admin, manager, cashier, waiter or kitchen"))
			return
		}
	}
	claims, ok := claimsFrom(r)
	if !ok {
		httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
		return
	}
	// Never patch a staff member of another org.
	existing, err := s.Store.GetStaff(r.Context(), pathID(r, "id"))
	if err != nil || existing.OrgID != claims.OrgID {
		httpx.ErrorJSON(w, r, httpx.ErrNotFound)
		return
	}
	// Owner (main admin) protection: the protected row is editable only by
	// itself, and even itself cannot deactivate/demote. Any other staff token
	// — including another admin — gets 403. Owner credential changes require
	// owner auth (self session), never a manager PIN.
	if existing.IsProtected {
		if claims.ActorID != existing.ID {
			httpx.ErrorJSON(w, r, httpx.NewError(403, "owner_protected", "Main admin (owner) can only be edited by itself"))
			return
		}
		if (p.IsActive != nil && !*p.IsActive) || (p.Role != nil && *p.Role != "admin") {
			httpx.ErrorJSON(w, r, httpx.NewError(403, "owner_protected", "Main admin (owner) cannot be deactivated or demoted"))
			return
		}
	}
	// Managers cannot edit any regular admin row. Protected (owner) rows are
	// already limited to self-only above.
	if !existing.IsProtected && existing.Role == "admin" && claims.Role == "manager" {
		httpx.ErrorJSON(w, r, httpx.NewError(403, "admin_only", "Only admins can edit admin staff"))
		return
	}
	// Self guards for all roles: no self-deactivation, no self-demotion.
	if claims.ActorID == existing.ID {
		if p.IsActive != nil && !*p.IsActive {
			httpx.ErrorJSON(w, r, httpx.NewError(403, "self_deactivation", "You cannot deactivate yourself"))
			return
		}
		if p.Role != nil && *p.Role != existing.Role {
			httpx.ErrorJSON(w, r, httpx.NewError(403, "self_demotion", "You cannot change your own role"))
			return
		}
		// Owner PIN reset via POS is allowed only for owner-self (already
		// checked above); non-owner self PIN changes fall through.
	}
	// Non-self PIN reset on a protected row is already rejected above
	// (owner_protected), so reaching here with a PIN means self or regular row.
	effectiveRole := existing.Role
	if p.Role != nil {
		effectiveRole = *p.Role
	}
	effectiveOutlet := existing.OutletID
	if p.OutletID != nil {
		effectiveOutlet = p.OutletID
	}
	if effectiveRole == "waiter" || effectiveRole == "kitchen" {
		if effectiveOutlet == nil || *effectiveOutlet == "" {
			if outID := outletScope(r); outID != "" {
				effectiveOutlet = &outID
				p.OutletID = &outID
			} else {
				httpx.ErrorJSON(w, r, httpx.NewError(400, "outlet_required", "A waiter or kitchen staff must be assigned to a specific outlet"))
				return
			}
		}
	}
	if p.OutletID != nil && *p.OutletID != "" {
		out, err := s.Store.GetOutlet(r.Context(), *p.OutletID)
		if err != nil || out.OrgID != claims.OrgID {
			httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_outlet", "Outlet does not belong to this organization"))
			return
		}
	}
	var pinHash *string
	if p.PIN != nil && *p.PIN != "" {
		if len(*p.PIN) < 4 || len(*p.PIN) > 6 || !allDigits(*p.PIN) {
			httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_pin", "PIN must be 4-6 digits"))
			return
		}
		hash, err := s.Auth.HashPIN(*p.PIN)
		if err != nil {
			httpx.ErrorJSON(w, r, err)
			return
		}
		pinHash = &hash
	}
	st, err := s.Store.UpdateStaff(r.Context(), pathID(r, "id"), p, pinHash)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, st)
}

func allDigits(s string) bool {
	for _, c := range s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return len(s) > 0
}

func (s *Server) handleListOutlets(w http.ResponseWriter, r *http.Request) {
	orgID, err := s.orgFromCodeOrDemo(r)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	out, err := s.Store.ListOutlets(r.Context(), orgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"outlets": out})
}

// orgFromCodeOrDemo resolves the tenant for legacy public endpoints: explicit
// ?org_code= wins; otherwise the demo org is returned for backward compat.
func (s *Server) orgFromCodeOrDemo(r *http.Request) (string, error) {
	if code := r.URL.Query().Get("org_code"); code != "" {
		org, err := s.Store.GetOrgByCode(r.Context(), code)
		if err != nil {
			return "", err
		}
		return org.ID, nil
	}
	return "org-01", nil
}

func (s *Server) handleGetOutlet(w http.ResponseWriter, r *http.Request) {
	o, err := s.Store.GetOutlet(r.Context(), pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if c, ok := claimsFrom(r); ok && c.Scope == auth.ScopeStaff && c.OrgID != o.OrgID {
		httpx.ErrorJSON(w, r, httpx.ErrNotFound)
		return
	}
	httpx.JSON(w, http.StatusOK, o)
}
