package api

import (
	"net/http"
	"strings"

	"foodpos/backend/internal/httpx"
)

type DeviceTokenReq struct {
	Token    string `json:"token"`
	Platform string `json:"platform"`
}

func (s *Server) handleRegisterDeviceToken(w http.ResponseWriter, r *http.Request) {
	var req DeviceTokenReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}

	token := strings.TrimSpace(req.Token)
	if token == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(http.StatusBadRequest, "missing_token", "token is required"))
		return
	}

	platform := strings.TrimSpace(req.Platform)
	if platform == "" {
		platform = "android"
	}

	orgID := ""
	outletID := ""
	staffID := ""

	if c, ok := claimsFrom(r); ok {
		orgID = c.OrgID
		outletID = c.OutletID
		staffID = c.ActorID
	}

	if outletID == "" {
		outletID = r.URL.Query().Get("outlet_id")
	}

	if err := s.Store.UpsertDeviceToken(r.Context(), token, orgID, outletID, staffID, platform); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}

	httpx.JSON(w, http.StatusOK, map[string]any{
		"registered": true,
		"token":      token,
	})
}

func (s *Server) handleUnregisterDeviceToken(w http.ResponseWriter, r *http.Request) {
	var req DeviceTokenReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}

	token := strings.TrimSpace(req.Token)
	if token == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(http.StatusBadRequest, "missing_token", "token is required"))
		return
	}

	if err := s.Store.DeleteDeviceToken(r.Context(), token); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}

	httpx.JSON(w, http.StatusOK, map[string]any{
		"unregistered": true,
	})
}
