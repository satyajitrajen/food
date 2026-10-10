package api

import (
	"net/http"

	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/models"
	"foodpos/backend/internal/store"
)

// Edit / delete endpoints for back-office records, order cancel and the
// manager's full staff list. Every change is published so other terminals
// refresh.

func (s *Server) handlePatchCustomer(w http.ResponseWriter, r *http.Request) {
	var p models.CustomerPatch
	if err := httpx.Decode(r, &p); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	outletID := outletScope(r)
	c, err := s.Store.PatchCustomer(r.Context(), outletID, pathID(r, "id"), p)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	s.publish(r, "customer.changed", outletID, c)
	httpx.JSON(w, http.StatusOK, c)
}

func (s *Server) handleDeleteCustomer(w http.ResponseWriter, r *http.Request) {
	outletID := outletScope(r)
	id := pathID(r, "id")
	if err := s.Store.DeleteCustomer(r.Context(), outletID, id); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	s.publish(r, "customer.changed", outletID, map[string]any{"id": id, "deleted": true})
	httpx.JSON(w, http.StatusOK, map[string]any{"deleted": true})
}

func (s *Server) handlePatchSupplier(w http.ResponseWriter, r *http.Request) {
	var p models.SupplierPatch
	if err := httpx.Decode(r, &p); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	outletID := outletScope(r)
	sup, err := s.Store.PatchSupplier(r.Context(), outletID, pathID(r, "id"), p)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	s.publish(r, "supplier.changed", outletID, sup)
	httpx.JSON(w, http.StatusOK, sup)
}

func (s *Server) handleDeleteSupplier(w http.ResponseWriter, r *http.Request) {
	outletID := outletScope(r)
	id := pathID(r, "id")
	if err := s.Store.DeleteSupplier(r.Context(), outletID, id); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	s.publish(r, "supplier.changed", outletID, map[string]any{"id": id, "deleted": true})
	httpx.JSON(w, http.StatusOK, map[string]any{"deleted": true})
}

func (s *Server) handlePatchInventoryItem(w http.ResponseWriter, r *http.Request) {
	var p models.InventoryPatch
	if err := httpx.Decode(r, &p); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	outletID := outletScope(r)
	item, err := s.Store.PatchInventoryItem(r.Context(), outletID, pathID(r, "id"), p)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	s.publish(r, "inventory.changed", outletID, item)
	httpx.JSON(w, http.StatusOK, item)
}

func (s *Server) handleDeleteInventoryItem(w http.ResponseWriter, r *http.Request) {
	outletID := outletScope(r)
	id := pathID(r, "id")
	if err := s.Store.DeleteInventoryItem(r.Context(), outletID, id); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	s.publish(r, "inventory.changed", outletID, map[string]any{"id": id, "deleted": true})
	httpx.JSON(w, http.StatusOK, map[string]any{"deleted": true})
}

func (s *Server) handlePatchExpense(w http.ResponseWriter, r *http.Request) {
	var p models.ExpensePatch
	if err := httpx.Decode(r, &p); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	exp, err := s.Store.GetExpense(r.Context(), pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if !sameOutlet(r, exp.OutletID) {
		httpx.ErrorJSON(w, r, httpx.ErrNotFound)
		return
	}
	updated, shiftID, err := s.Store.PatchExpense(r.Context(), exp.ID, p)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if shiftID != "" {
		if sh, err := s.Store.GetShift(r.Context(), shiftID); err == nil {
			s.publish(r, "shift.updated", exp.OutletID, sh)
		}
	}
	s.publish(r, "expense.changed", exp.OutletID, updated)
	httpx.JSON(w, http.StatusOK, updated)
}

// handleCancelOrder voids an unpaid order (wrong table, customer left).
// After a KOT reached the kitchen a manager has to approve it.
func (s *Server) handleCancelOrder(w http.ResponseWriter, r *http.Request) {
	var req models.OrderCancelReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	o, err := s.loadOrderForCaller(r, pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if store.IsClosedStatus(o.Status) {
		httpx.ErrorJSON(w, r, store.ErrOrderClosed)
		return
	}
	hasKOT, err := s.Store.OrderHasKOT(r.Context(), o.ID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if hasKOT {
		if c, _ := claimsFrom(r); c == nil || !isManagerRole(c.Role) {
			if err := s.requireManagerPIN(r.Context(), derefStr(req.ManagerPin)); err != nil {
				httpx.ErrorJSON(w, r, err)
				return
			}
		}
	}
	updated, err := s.Store.CancelOpenOrder(r.Context(), o.ID, req.Reason)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	s.afterOrderWrite(r, updated)
	if kots, err := s.Store.ListKOTs(r.Context(), updated.OutletID, ""); err == nil {
		for _, k := range kots {
			if k.OrderID == updated.ID {
				s.publish(r, "kot.updated", updated.OutletID, k)
			}
		}
	}
	httpx.JSON(w, http.StatusOK, updated)
}

// handleListAllStaff is the manager's staff list, including deactivated
// staff so they can be reactivated.
func (s *Server) handleListAllStaff(w http.ResponseWriter, r *http.Request) {
	c, ok := claimsFrom(r)
	if !ok || c.OrgID == "" {
		httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
		return
	}
	list, err := s.Store.ListAllStaff(r.Context(), c.OrgID, outletScope(r))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if list == nil {
		list = []models.Staff{}
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"staff": list})
}

// statusRecorder remembers the status a handler wrote.
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (w *statusRecorder) WriteHeader(code int) {
	w.status = code
	w.ResponseWriter.WriteHeader(code)
}

// announce publishes "<resource>.changed" after a successful write so other
// terminals re-fetch that resource (menu, staff, customers, ...).
func (s *Server) announce(resource string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
			next.ServeHTTP(rec, r)
			if rec.status < 300 {
				if outletID := outletScope(r); outletID != "" {
					s.publish(r, resource+".changed", outletID, map[string]any{"resource": resource})
				}
			}
		})
	}
}
