package api

import (
	"net/http"
	"strings"

	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/models"
)

// Self-service profile for the signed-in staff member. Name, mobile and photo
// are the person's own details; role, outlet and active status stay with
// managers (PATCH /staff/{id}).

func (s *Server) handleGetMe(w http.ResponseWriter, r *http.Request) {
	claims, ok := claimsFrom(r)
	if !ok {
		httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
		return
	}
	st, err := s.Store.GetStaff(r.Context(), claims.ActorID)
	if err != nil || st.OrgID != claims.OrgID {
		httpx.ErrorJSON(w, r, httpx.ErrNotFound)
		return
	}
	httpx.JSON(w, http.StatusOK, st.Staff)
}

func (s *Server) handlePatchMe(w http.ResponseWriter, r *http.Request) {
	var req models.MePatch
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	claims, ok := claimsFrom(r)
	if !ok {
		httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
		return
	}
	existing, err := s.Store.GetStaff(r.Context(), claims.ActorID)
	if err != nil || existing.OrgID != claims.OrgID {
		httpx.ErrorJSON(w, r, httpx.ErrNotFound)
		return
	}
	p := models.StaffPatch{}
	if req.Name != nil {
		name := strings.TrimSpace(*req.Name)
		if name == "" || len(name) > 60 {
			httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_name", "Name must be 1-60 characters"))
			return
		}
		p.Name = &name
	}
	if req.Mobile != nil {
		mobile := strings.TrimSpace(*req.Mobile)
		if mobile != "" && (len(mobile) != 10 || !allDigits(mobile)) {
			httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_mobile", "Mobile must be 10 digits"))
			return
		}
		p.Mobile = &mobile
	}
	if req.AvatarURL != nil {
		url := strings.TrimSpace(*req.AvatarURL)
		// Only this server's uploads (or clearing) — never arbitrary URLs.
		if url != "" && !strings.HasPrefix(url, "/media/") {
			httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_avatar", "Upload the photo with /me/avatar first"))
			return
		}
		p.AvatarURL = &url
	}
	st, err := s.Store.UpdateStaff(r.Context(), claims.ActorID, p, nil)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, st)
}

// handleChangeMyPIN changes the caller's own PIN after re-checking the
// current one. Wrong current PINs count toward the same 5-strike lockout as
// login, so this can't be used to guess a PIN.
func (s *Server) handleChangeMyPIN(w http.ResponseWriter, r *http.Request) {
	var req models.ChangePINReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	claims, ok := claimsFrom(r)
	if !ok {
		httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
		return
	}
	if len(req.NewPIN) < 4 || len(req.NewPIN) > 6 || !allDigits(req.NewPIN) {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_pin", "PIN must be 4-6 digits"))
		return
	}
	if req.NewPIN == req.CurrentPIN {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "same_pin", "Choose a PIN different from the current one"))
		return
	}
	lockKey := "login:" + claims.ActorID
	if err := s.pinLockedErr(w, lockKey); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	existing, err := s.Store.GetStaff(r.Context(), claims.ActorID)
	if err != nil || existing.OrgID != claims.OrgID {
		httpx.ErrorJSON(w, r, httpx.ErrNotFound)
		return
	}
	if !s.Auth.CheckPIN(existing.PINHash, req.CurrentPIN) {
		if s.pinLockout().Fail(lockKey) {
			httpx.ErrorJSON(w, r, errPINLocked)
			return
		}
		httpx.ErrorJSON(w, r, httpx.NewError(400, "wrong_pin", "Current PIN is incorrect"))
		return
	}
	s.pinLockout().Success(lockKey)
	hash, err := s.Auth.HashPIN(req.NewPIN)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if _, err := s.Store.UpdateStaff(r.Context(), claims.ActorID, models.StaffPatch{}, &hash); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"changed": true})
}
