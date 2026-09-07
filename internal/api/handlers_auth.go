package api

import (
	"context"
	"net/http"
	"time"

	"foodpos/backend/internal/auth"
	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/models"
)

type loginReq struct {
	StaffID  string `json:"staff_id"`
	PIN      string `json:"pin"`
	OutletID string `json:"outlet_id,omitempty"`
}

type tokenResp struct {
	Token        string       `json:"token"`
	RefreshToken string       `json:"refresh_token,omitempty"`
	TokenType    string       `json:"token_type"`
	ExpiresAt    time.Time    `json:"expires_at"`
	Staff        models.Staff `json:"staff"`
}

func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	var req loginReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if req.StaffID == "" || req.PIN == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_credentials", "staff_id and pin are required"))
		return
	}
	row, err := s.Store.GetStaff(r.Context(), req.StaffID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if !row.IsActive || !s.Auth.CheckPIN(row.PINHash, req.PIN) {
		httpx.ErrorJSON(w, r, httpx.NewError(401, "bad_credentials", "Invalid staff or PIN"))
		return
	}
	token, err := s.Auth.IssueToken(row.ID, row.Name, row.Role, req.OutletID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	refresh, hash := auth.NewRefreshToken()
	if err := s.Store.CreateRefreshToken(r.Context(), row.ID, hash, time.Now().Add(auth.RefreshTTL)); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, tokenResp{
		Token: token, RefreshToken: refresh, TokenType: "Bearer",
		ExpiresAt: time.Now().Add(auth.AccessTTL), Staff: row.Staff,
	})
}

type refreshReq struct {
	RefreshToken string `json:"refresh_token"`
}

// handleRefresh rotates the refresh token: the presented token is revoked
// and a new pair (access, refresh) is issued. Reuse of a revoked or expired
// token is rejected.
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
	rt, err := s.Store.GetRefreshToken(r.Context(), auth.HashToken(req.RefreshToken))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if rt.Revoked || time.Now().After(rt.ExpiresAt) {
		httpx.ErrorJSON(w, r, httpx.NewError(401, "invalid_refresh_token", "Refresh token is expired or revoked"))
		return
	}
	row, err := s.Store.GetStaff(r.Context(), rt.StaffID)
	if err != nil || !row.IsActive {
		httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
		return
	}
	if err := s.Store.RevokeRefreshToken(r.Context(), rt.ID); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	token, err := s.Auth.IssueToken(row.ID, row.Name, row.Role, "")
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	refresh, hash := auth.NewRefreshToken()
	if err := s.Store.CreateRefreshToken(r.Context(), row.ID, hash, time.Now().Add(auth.RefreshTTL)); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, tokenResp{
		Token: token, RefreshToken: refresh, TokenType: "Bearer",
		ExpiresAt: time.Now().Add(auth.AccessTTL), Staff: row.Staff,
	})
}

// handleWsTicket exchanges the authenticated JWT for a single-use, short-TTL
// connect ticket for GET /ws (EventSource cannot send an Authorization
// header, and a raw JWT in the query lands in proxy access logs).
func (s *Server) handleWsTicket(w http.ResponseWriter, r *http.Request) {
	if s.Tickets == nil {
		httpx.ErrorJSON(w, r, httpx.NewError(501, "tickets_disabled", "SSE tickets are not configured"))
		return
	}
	claims, ok := claimsFrom(r)
	if !ok {
		httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{
		"ticket":     s.Tickets.Issue(claims),
		"expires_at": time.Now().Add(auth.SSETicketTTL).UTC(),
	})
}

func (s *Server) handleLogout(w http.ResponseWriter, r *http.Request) {	var req refreshReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	rt, err := s.Store.GetRefreshToken(r.Context(), auth.HashToken(req.RefreshToken))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	_ = s.Store.RevokeRefreshToken(r.Context(), rt.ID)
	httpx.JSON(w, http.StatusOK, map[string]any{"revoked": true})
}

type managerPinReq struct {
	PIN string `json:"pin"`
}

type managerPinResp struct {
	Valid bool   `json:"valid"`
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
	if valid {
		httpx.JSON(w, http.StatusOK, managerPinResp{Valid: true, Staff: staff})
		return
	}
	httpx.JSON(w, http.StatusOK, managerPinResp{Valid: false})
}

// checkManagerPIN matches a PIN against active manager/admin staff (bcrypt).
func (s *Server) checkManagerPIN(ctx context.Context, pin string) (bool, *models.Staff, error) {
	if pin == "" {
		return false, nil, nil
	}
	staffList, err := s.Store.ListStaff(ctx)
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
// manager/admin PIN.
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

func (s *Server) handleListStaff(w http.ResponseWriter, r *http.Request) {
	list, err := s.Store.ListStaff(r.Context())
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
	hash, err := s.Auth.HashPIN(req.PIN)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	st, err := s.Store.CreateStaff(r.Context(), req, hash)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, st)
}

// handlePatchStaff partially updates a staff member (name, role, mobile,
// avatar, active flag) and can reset the PIN (B3 / PRD admin capability).
func (s *Server) handlePatchStaff(w http.ResponseWriter, r *http.Request) {
	var p models.StaffPatch
	if err := httpx.Decode(r, &p); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if p.Role != nil {
		switch *p.Role {
		case "admin", "manager", "cashier", "waiter":
		default:
			httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_role", "role must be admin, manager, cashier or waiter"))
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
	out, err := s.Store.ListOutlets(r.Context())
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"outlets": out})
}

func (s *Server) handleGetOutlet(w http.ResponseWriter, r *http.Request) {
	o, err := s.Store.GetOutlet(r.Context(), pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, o)
}
