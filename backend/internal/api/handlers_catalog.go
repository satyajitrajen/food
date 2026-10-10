package api

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"foodpos/backend/internal/auth"
	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/middleware"
	"foodpos/backend/internal/models"
	"foodpos/backend/internal/ws"
)

func (s *Server) handleListTables(w http.ResponseWriter, r *http.Request) {
	outletID := r.URL.Query().Get("outlet_id")
	if outletID == "" {
		if c, ok := middleware.ClaimsFrom(r.Context()); ok && c.OutletID != "" {
			outletID = c.OutletID
		}
	}
	if outletID == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_outlet", "outlet_id is required"))
		return
	}
	tables, err := s.Store.ListTables(r.Context(), outletID, r.URL.Query().Get("floor"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"tables": tables})
}

func (s *Server) handleCreateTable(w http.ResponseWriter, r *http.Request) {
	s.withIdempotency(w, r, func() (int, any, error) {
		var t models.Table
		if err := httpx.Decode(r, &t); err != nil {
			return 0, nil, err
		}
		t.OutletID = outletScope(r)
		t.TableNumber = strings.TrimSpace(t.TableNumber)
		if t.OutletID == "" || t.TableNumber == "" || t.Seats <= 0 || t.Seats > 999 {
			return 0, nil, httpx.NewError(400, "invalid_table", "table_number and seats (1-999) are required")
		}
		created, err := s.Store.CreateTable(r.Context(), t)
		if err != nil {
			return 0, nil, err
		}
		s.publish(r, "table.updated", t.OutletID, created)
		return http.StatusCreated, created, nil
	})
}

func (s *Server) handlePatchTable(w http.ResponseWriter, r *http.Request) {
	var p models.TablePatch
	if err := httpx.Decode(r, &p); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	table, err := s.Store.GetTable(r.Context(), pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if !sameOutlet(r, table.OutletID) {
		httpx.ErrorJSON(w, r, httpx.ErrNotFound)
		return
	}
	if p.GuestCount != nil && (*p.GuestCount < 0 || *p.GuestCount > 999) {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_guests", "guest_count must be between 0 and 999"))
		return
	}
	if p.WaiterID != nil && *p.WaiterID != "" {
		if _, err := s.resolveWaiter(r, *p.WaiterID, table.OutletID); err != nil {
			httpx.ErrorJSON(w, r, err)
			return
		}
	}
	// Renaming/resizing a table is a layout change: managers only.
	if p.TableNumber != nil || p.Seats != nil {
		if c, ok := claimsFrom(r); !ok || (c.Role != "manager" && c.Role != "admin") {
			httpx.ErrorJSON(w, r, httpx.NewError(403, "forbidden", "Only managers can edit table layout"))
			return
		}
	}
	if p.TableNumber != nil {
		num := strings.TrimSpace(*p.TableNumber)
		if num == "" || len(num) > 20 {
			httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_table_number", "Table number must be 1-20 characters"))
			return
		}
		p.TableNumber = &num
	}
	if p.Seats != nil && (*p.Seats < 1 || *p.Seats > 50) {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_seats", "Seats must be between 1 and 50"))
		return
	}
	t, err := s.Store.PatchTable(r.Context(), table.ID, p)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	s.publish(r, "table.updated", t.OutletID, t)
	httpx.JSON(w, http.StatusOK, t)
}

func (s *Server) handleMoveTable(w http.ResponseWriter, r *http.Request) {
	s.withIdempotency(w, r, func() (int, any, error) {
		var req models.MoveTableReq
		if err := httpx.Decode(r, &req); err != nil {
			return 0, nil, err
		}
		// Ownership of both tables, occupancy and the re-home run in one tx.
		from, to, err := s.Store.MoveTable(r.Context(), outletScope(r), pathID(r, "id"), req.ToTableID)
		if err != nil {
			return 0, nil, err
		}
		s.publish(r, "table.updated", to.OutletID, from)
		s.publish(r, "table.updated", to.OutletID, to)
		if to.ActiveOrderID != nil {
			if o, err := s.Store.GetOrder(r.Context(), *to.ActiveOrderID); err == nil {
				s.publish(r, "order.updated", o.OutletID, o)
			}
		}
		return http.StatusOK, map[string]any{"moved_to": to}, nil
	})
}

func (s *Server) handleMergeTable(w http.ResponseWriter, r *http.Request) {
	s.withIdempotency(w, r, func() (int, any, error) {
		var req models.MergeTableReq
		if err := httpx.Decode(r, &req); err != nil {
			return 0, nil, err
		}
		primary, err := s.Store.MergeTables(r.Context(), outletScope(r), pathID(r, "id"), req.SecondaryTableID)
		if err != nil {
			return 0, nil, err
		}
		s.publish(r, "table.updated", primary.OutletID, primary)
		if sec, err := s.Store.GetTable(r.Context(), req.SecondaryTableID); err == nil {
			s.publish(r, "table.updated", sec.OutletID, sec)
		}
		return http.StatusOK, map[string]any{"merged": true, "table": primary}, nil
	})
}

func (s *Server) handleUnmergeTable(w http.ResponseWriter, r *http.Request) {
	existing, err := s.Store.GetTable(r.Context(), pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if !sameOutlet(r, existing.OutletID) {
		httpx.ErrorJSON(w, r, httpx.ErrNotFound)
		return
	}
	t, err := s.Store.UnmergeTable(r.Context(), existing.ID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	s.publish(r, "table.updated", t.OutletID, t)
	httpx.JSON(w, http.StatusOK, map[string]any{"unmerged": true})
}

func strPtr(s string) *string { return &s }

func derefStr(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

// publish fans an event out to the outlet's live SSE clients. Push
// notifications are separate (notifyOutlet) and only fire for the events a
// phone should buzz for.
func (s *Server) publish(_ *http.Request, evtType, outletID string, payload any) {
	if s.Hub == nil {
		return
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return
	}
	s.Hub.Publish(ws.Event{Type: evtType, OutletID: outletID, Payload: body, Timestamp: time.Now().UTC()})
}

// notifyOutlet pushes a notification to the devices registered to an outlet
// (fire-and-forget; a no-op when FCM is not configured).
func (s *Server) notifyOutlet(outletID, title, body string, data map[string]string) {
	if s.Notifier == nil || !s.Notifier.Enabled() || outletID == "" {
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		tokens, err := s.Store.ListDeviceTokensByOutlet(ctx, outletID)
		if err != nil || len(tokens) == 0 {
			return
		}
		if data == nil {
			data = map[string]string{}
		}
		data["outlet_id"] = outletID
		s.Notifier.SendToTokens(ctx, tokens, title, body, data)
	}()
}

func (s *Server) handleListMenu(w http.ResponseWriter, r *http.Request) {
	outletID := r.URL.Query().Get("outlet_id")
	if outletID == "" {
		if c, ok := middleware.ClaimsFrom(r.Context()); ok && c.OutletID != "" {
			outletID = c.OutletID
		}
	}
	if outletID == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_outlet", "outlet_id is required"))
		return
	}
	items, err := s.Store.ListMenu(r.Context(), outletID, r.URL.Query().Get("category_id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"menu_items": items})
}

func (s *Server) handleGetMenuItem(w http.ResponseWriter, r *http.Request) {
	m, err := s.Store.GetMenuItem(r.Context(), pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if c, ok := claimsFrom(r); ok && c.Scope == auth.ScopeStaff && c.OutletID != m.OutletID {
		httpx.ErrorJSON(w, r, httpx.ErrNotFound)
		return
	}
	httpx.JSON(w, http.StatusOK, m)
}

func (s *Server) handleCreateMenuItem(w http.ResponseWriter, r *http.Request) {
	s.withIdempotency(w, r, func() (int, any, error) {
		var req models.MenuItemUpsert
		if err := httpx.Decode(r, &req); err != nil {
			return 0, nil, err
		}
		outletID := outletScope(r)
		if outletID == "" {
			return 0, nil, httpx.NewError(400, "missing_outlet", "outlet_id is required")
		}
		// Admin clients send the category *name*; resolve to the real id.
		if req.CategoryID != nil {
			id, err := s.Store.CategoryID(r.Context(), outletID, *req.CategoryID)
			if err != nil {
				return 0, nil, err
			}
			req.CategoryID = &id
		}
		m, err := s.Store.CreateMenuItem(r.Context(), outletID, req)
		if err != nil {
			return 0, nil, err
		}
		return http.StatusCreated, m, nil
	})
}

func (s *Server) handlePatchMenuItem(w http.ResponseWriter, r *http.Request) {
	var req models.MenuItemUpsert
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	item, err := s.Store.GetMenuItem(r.Context(), pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if c, ok := claimsFrom(r); ok && c.Scope == auth.ScopeStaff && c.OutletID != item.OutletID {
		httpx.ErrorJSON(w, r, httpx.ErrNotFound)
		return
	}
	if req.CategoryID != nil {
		id, err := s.Store.CategoryID(r.Context(), item.OutletID, *req.CategoryID)
		if err != nil {
			httpx.ErrorJSON(w, r, err)
			return
		}
		req.CategoryID = &id
	}
	m, err := s.Store.PatchMenuItem(r.Context(), item.ID, req)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, m)
}

func (s *Server) handleDeleteMenuItem(w http.ResponseWriter, r *http.Request) {
	item, err := s.Store.GetMenuItem(r.Context(), pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if c, ok := claimsFrom(r); ok && c.Scope == auth.ScopeStaff && c.OutletID != item.OutletID {
		httpx.ErrorJSON(w, r, httpx.ErrNotFound)
		return
	}
	if err := s.Store.DeleteMenuItem(r.Context(), item.ID); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"deleted": true})
}

func (s *Server) handleGetSettings(w http.ResponseWriter, r *http.Request) {
	st, err := s.Store.GetSettings(r.Context(), outletScope(r))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, st)
}

// handlePutSettings saves the caller's OWN outlet settings: the target is
// always the claims-bound outlet (a body outlet_id is ignored, so a manager
// can never write another tenant's settings).
func (s *Server) handlePutSettings(w http.ResponseWriter, r *http.Request) {
	var st models.Settings
	if err := httpx.Decode(r, &st); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	st.OutletID = outletScope(r)
	if st.OutletID == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_outlet", "outlet_id is required"))
		return
	}
	switch {
	case st.GSTPercent < 0 || st.GSTPercent > 28:
		httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_tax", "gst_percent must be between 0 and 28"))
		return
	case st.ServicePercent < 0 || st.ServicePercent > 20:
		httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_service", "service_percent must be between 0 and 20"))
		return
	case st.PackagingPaise < 0 || st.DeliveryPaise < 0:
		httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_charge", "charges cannot be negative"))
		return
	}
	if err := s.Store.PutSettings(r.Context(), st); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, st)
}

// handlePatchOutlet updates the caller's own outlet profile (manager+): the
// bill header (name/address/phone/email/GSTIN/FSSAI) and the timezone used
// for report day boundaries.
func (s *Server) handlePatchOutlet(w http.ResponseWriter, r *http.Request) {
	var p models.OutletPatch
	if err := httpx.Decode(r, &p); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	o, err := s.Store.GetOutlet(r.Context(), pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	c, _ := claimsFrom(r)
	if c == nil || c.OrgID != o.OrgID {
		httpx.ErrorJSON(w, r, httpx.ErrNotFound)
		return
	}
	for _, f := range []**string{&p.Name, &p.Address, &p.Phone, &p.Email, &p.GSTIN, &p.FSSAI, &p.Timezone} {
		if *f != nil {
			v := strings.TrimSpace(**f)
			*f = &v
		}
	}
	if p.Name != nil && *p.Name == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_outlet", "name cannot be empty"))
		return
	}
	if p.Timezone != nil {
		if _, err := time.LoadLocation(*p.Timezone); err != nil || *p.Timezone == "" || *p.Timezone == "Local" {
			httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_timezone", "timezone must be an IANA zone such as Asia/Kolkata"))
			return
		}
	}
	if p.Email != nil && *p.Email != "" && !strings.Contains(*p.Email, "@") {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_email", "email is not valid"))
		return
	}
	updated, err := s.Store.PatchOutlet(r.Context(), o.ID, p)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	s.publish(r, "outlet.updated", o.ID, updated)
	httpx.JSON(w, http.StatusOK, updated)
}

// handleDeleteTable removes a free table from the floor plan (manager+).
func (s *Server) handleDeleteTable(w http.ResponseWriter, r *http.Request) {
	table, err := s.Store.GetTable(r.Context(), pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if !sameOutlet(r, table.OutletID) {
		httpx.ErrorJSON(w, r, httpx.ErrNotFound)
		return
	}
	if err := s.Store.DeleteTable(r.Context(), table.ID); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	s.publish(r, "table.deleted", table.OutletID, map[string]string{"id": table.ID, "outlet_id": table.OutletID})
	httpx.JSON(w, http.StatusOK, map[string]any{"deleted": true})
}
