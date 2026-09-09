package api

import (
	"encoding/json"
	"net/http"
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
	var t models.Table
	if err := httpx.Decode(r, &t); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if t.OutletID == "" || t.TableNumber == "" || t.Seats <= 0 {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_table", "outlet_id, table_number and seats are required"))
		return
	}
	created, err := s.Store.CreateTable(r.Context(), t)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	s.publish(r, "table.updated", t.OutletID, created)
	httpx.JSON(w, http.StatusCreated, created)
}

func (s *Server) handlePatchTable(w http.ResponseWriter, r *http.Request) {
	var p models.TablePatch
	if err := httpx.Decode(r, &p); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	t, err := s.Store.PatchTable(r.Context(), pathID(r, "id"), p)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	s.publish(r, "table.updated", t.OutletID, t)
	httpx.JSON(w, http.StatusOK, t)
}

func (s *Server) handleMoveTable(w http.ResponseWriter, r *http.Request) {
	var req models.MoveTableReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	from, err := s.Store.GetTable(r.Context(), pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if from.ActiveOrderID == nil {
		httpx.ErrorJSON(w, r, httpx.NewError(409, "no_active_order", "Source table has no active order"))
		return
	}
	to, err := s.Store.GetTable(r.Context(), req.ToTableID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if busy, _, err := s.Store.TableHasActiveOrder(r.Context(), to.ID); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	} else if busy {
		httpx.ErrorJSON(w, r, httpx.ErrTableOccupied)
		return
	}
	order, err := s.Store.GetOrder(r.Context(), *from.ActiveOrderID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if err := s.Store.PatchOrderTable(r.Context(), order.ID, to.ID, to.TableNumber); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if err := s.Store.UpdateTableForOrder(r.Context(), to.ID, order.ID, order.GrandTotalPaise, order.GuestCount); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	// Clear source table.
	if _, err := s.Store.PatchTable(r.Context(), from.ID, models.TablePatch{Status: strPtr("available")}); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	_, _ = s.Store.DB.Exec(`UPDATE tables SET active_order_id = NULL, current_amount = 0, guest_count = 0 WHERE id = ?`, from.ID)
	s.publish(r, "table.updated", from.OutletID, to)
	httpx.JSON(w, http.StatusOK, map[string]any{"moved_to": to})
}

func (s *Server) handleMergeTable(w http.ResponseWriter, r *http.Request) {
	var req models.MergeTableReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	primary, err := s.Store.GetTable(r.Context(), pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	secondary, err := s.Store.GetTable(r.Context(), req.SecondaryTableID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if primary.ID == secondary.ID {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_merge", "Cannot merge a table with itself"))
		return
	}
	// Re-home the secondary's active order onto the primary.
	if secondary.ActiveOrderID != nil {
		order, err := s.Store.GetOrder(r.Context(), *secondary.ActiveOrderID)
		if err != nil {
			httpx.ErrorJSON(w, r, err)
			return
		}
		if err := s.Store.PatchOrderTable(r.Context(), order.ID, primary.ID, primary.TableNumber); err != nil {
			httpx.ErrorJSON(w, r, err)
			return
		}
	}
	_, _ = s.Store.DB.Exec(`UPDATE tables SET merged_with_table_id = ?, active_order_id = NULL,
		current_amount = 0, guest_count = 0 WHERE id = ?`, primary.ID, secondary.ID)
	s.publish(r, "table.updated", primary.OutletID, primary)
	httpx.JSON(w, http.StatusOK, map[string]any{"merged": true})
}

func (s *Server) handleUnmergeTable(w http.ResponseWriter, r *http.Request) {
	t, err := s.Store.PatchTable(r.Context(), pathID(r, "id"), models.TablePatch{})
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if _, err := s.Store.DB.Exec(`UPDATE tables SET merged_with_table_id = NULL WHERE id = ?`, t.ID); err != nil {
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
	var req models.MenuItemUpsert
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	outletID := r.URL.Query().Get("outlet_id")
	if outletID == "" {
		if c, ok := middleware.ClaimsFrom(r.Context()); ok && c.OutletID != "" {
			outletID = c.OutletID
		}
	}
	// Admin clients send the category *name*; resolve to the real id.
	if req.CategoryID != nil {
		id, err := s.Store.CategoryID(r.Context(), outletID, *req.CategoryID)
		if err != nil {
			httpx.ErrorJSON(w, r, err)
			return
		}
		req.CategoryID = &id
	}
	m, err := s.Store.CreateMenuItem(r.Context(), outletID, req)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, m)
}

func (s *Server) handlePatchMenuItem(w http.ResponseWriter, r *http.Request) {
	var req models.MenuItemUpsert
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if req.CategoryID != nil {
		item, err := s.Store.GetMenuItem(r.Context(), pathID(r, "id"))
		if err != nil {
			httpx.ErrorJSON(w, r, err)
			return
		}
		id, err := s.Store.CategoryID(r.Context(), item.OutletID, *req.CategoryID)
		if err != nil {
			httpx.ErrorJSON(w, r, err)
			return
		}
		req.CategoryID = &id
	}
	m, err := s.Store.PatchMenuItem(r.Context(), pathID(r, "id"), req)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, m)
}

func (s *Server) handleDeleteMenuItem(w http.ResponseWriter, r *http.Request) {
	if err := s.Store.DeleteMenuItem(r.Context(), pathID(r, "id")); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"deleted": true})
}

func (s *Server) handleGetSettings(w http.ResponseWriter, r *http.Request) {
	outletID := r.URL.Query().Get("outlet_id")
	if outletID == "" {
		if c, ok := middleware.ClaimsFrom(r.Context()); ok && c.OutletID != "" {
			outletID = c.OutletID
		}
	}
	st, err := s.Store.GetSettings(r.Context(), outletID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, st)
}

func (s *Server) handlePutSettings(w http.ResponseWriter, r *http.Request) {
	var st models.Settings
	if err := httpx.Decode(r, &st); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	// Clients may omit outlet_id; resolve it like every other outlet-scoped
	// route so the settings row always lands on a real outlet (FK-guarded).
	if st.OutletID == "" {
		st.OutletID = outletScope(r)
	}
	if st.OutletID == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_outlet", "outlet_id is required"))
		return
	}
	if err := s.Store.PutSettings(r.Context(), st); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, st)
}
