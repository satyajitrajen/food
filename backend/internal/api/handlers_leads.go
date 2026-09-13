package api

// Landing lead capture: public write (rate-limited) + superadmin list.

import (
	"log/slog"
	"net/http"
	"strings"
	"time"

	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/models"
	"foodpos/backend/internal/store"
)

func (s *Server) handleCreateLead(w http.ResponseWriter, r *http.Request) {
	var req models.LeadCreateReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	req.RestaurantName = strings.TrimSpace(req.RestaurantName)
	req.ContactName = strings.TrimSpace(req.ContactName)
	req.Phone = strings.TrimSpace(req.Phone)
	if len(req.RestaurantName) < 2 {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_fields", "restaurant_name is required"))
		return
	}
	digits := strings.Map(func(c rune) rune {
		if c >= '0' && c <= '9' {
			return c
		}
		return -1
	}, req.Phone)
	if len(digits) < 10 || len(digits) > 12 {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_phone", "phone must be a 10-12 digit number"))
		return
	}
	source := strings.TrimSpace(req.Source)
	if source == "" {
		source = "landing"
	}
	lead := &models.Lead{
		ID:             store.NewID("lead"),
		RestaurantName: req.RestaurantName,
		ContactName:    req.ContactName,
		Phone:          digits,
		City:           strings.TrimSpace(req.City),
		OutletFormat:   strings.TrimSpace(req.OutletFormat),
		PlanInterest:   strings.TrimSpace(req.PlanInterest),
		Source:         source,
		Status:         "new",
		CreatedAt:      store.TimeStr(time.Now()),
	}
	if err := s.Store.CreateLead(r.Context(), lead); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	slog.Info("lead captured", "id", lead.ID, "restaurant", lead.RestaurantName, "phone", lead.Phone, "plan", lead.PlanInterest)
	httpx.JSON(w, http.StatusCreated, map[string]any{"id": lead.ID})
}

func (s *Server) handleAdminListLeads(w http.ResponseWriter, r *http.Request) {
	leads, err := s.Store.ListLeads(r.Context(), queryInt(r, "limit", 200))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if leads == nil {
		leads = []models.Lead{}
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"leads": leads})
}
