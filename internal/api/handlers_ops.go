package api

import (
	"net/http"

	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/middleware"
	"foodpos/backend/internal/models"
	"foodpos/backend/internal/service"
	"foodpos/backend/internal/store"
)

// ---- Shifts ----

func (s *Server) handleCurrentShift(w http.ResponseWriter, r *http.Request) {
	outletID := outletScope(r)
	if outletID == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_outlet", "outlet_id is required"))
		return
	}
	shift, err := s.Store.GetCurrentShift(r.Context(), outletID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"shift": shift})
}

func (s *Server) handleListShifts(w http.ResponseWriter, r *http.Request) {
	outletID := outletScope(r)
	if outletID == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_outlet", "outlet_id is required"))
		return
	}
	shifts, err := s.Store.ListShifts(r.Context(), outletID, queryInt(r, "limit", 50))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"shifts": shifts})
}

func (s *Server) handleOpenShift(w http.ResponseWriter, r *http.Request) {
	s.withIdempotency(w, r, func() (int, any, error) {
		var req models.ShiftOpenReq
		if err := httpx.Decode(r, &req); err != nil {
			return 0, nil, err
		}
		outletID := outletScope(r)
		if outletID == "" {
			return 0, nil, httpx.NewError(400, "missing_outlet", "outlet_id is required")
		}
		if req.OpeningPaise < 0 {
			return 0, nil, httpx.ErrInvalidAmount
		}
		if existing, err := s.Store.GetCurrentShift(r.Context(), outletID); err != nil {
			return 0, nil, err
		} else if existing != nil {
			return 0, nil, httpx.NewError(409, "shift_already_open", "Outlet already has an open shift")
		}
		claims, _ := claimsFrom(r)
		shift, err := s.Store.OpenShift(r.Context(), outletID, claims.StaffID, claims.Name, req)
		if err != nil {
			return 0, nil, err
		}
		s.publish(r, "shift.updated", outletID, shift)
		return http.StatusCreated, shift, nil
	})
}

func (s *Server) handleCloseShift(w http.ResponseWriter, r *http.Request) {
	var req models.ShiftCloseReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	outletID := outletScope(r)
	if outletID == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_outlet", "outlet_id is required"))
		return
	}
	shift, err := s.Store.GetCurrentShift(r.Context(), outletID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if shift == nil {
		httpx.ErrorJSON(w, r, httpx.NewError(409, "no_open_shift", "No open shift to close"))
		return
	}
	closed, err := s.Store.CloseShift(r.Context(), shift.ID, req)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	s.publish(r, "shift.updated", outletID, closed)
	httpx.JSON(w, http.StatusOK, closed)
}

func (s *Server) handleCashMove(w http.ResponseWriter, r *http.Request) {
	var req models.CashMoveReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if req.Amount <= 0 {
		httpx.ErrorJSON(w, r, httpx.ErrInvalidAmount)
		return
	}
	if req.Type != "cash_in" && req.Type != "cash_out" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_type", "type must be cash_in or cash_out"))
		return
	}
	outletID := outletScope(r)
	shift, err := s.Store.GetCurrentShift(r.Context(), outletID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if shift == nil {
		httpx.ErrorJSON(w, r, httpx.NewError(409, "no_open_shift", "Open a shift before cash movements"))
		return
	}
	if req.Type == "cash_out" && req.Amount > shift.ExpectedCash() {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "insufficient_drawer",
			"Cash out exceeds the expected drawer balance"))
		return
	}
	claims, _ := claimsFrom(r)
	tx, err := s.Store.AddCashMove(r.Context(), shift.ID, claims.StaffID, claims.Name, req.Type, req.Amount, req.Reason, req.Reference)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	updated, _ := s.Store.GetCurrentShift(r.Context(), outletID)
	s.publish(r, "shift.updated", outletID, updated)
	httpx.JSON(w, http.StatusCreated, tx)
}

// ---- Expenses ----

func (s *Server) handleListExpenses(w http.ResponseWriter, r *http.Request) {
	outletID := outletScope(r)
	if outletID == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_outlet", "outlet_id is required"))
		return
	}
	list, err := s.Store.ListExpenses(r.Context(), outletID, r.URL.Query().Get("range"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"expenses": list})
}

func (s *Server) handleCreateExpense(w http.ResponseWriter, r *http.Request) {
	s.withIdempotency(w, r, func() (int, any, error) {
		var req models.ExpenseCreate
		if err := httpx.Decode(r, &req); err != nil {
			return 0, nil, err
		}
		outletID := outletScope(r)
		claims, _ := claimsFrom(r)
		exp, err := s.Store.CreateExpense(r.Context(), outletID, req, strPtr(claims.StaffID))
		if err != nil {
			return 0, nil, err
		}
		// Cash expenses reduce the drawer of the open shift.
		if exp.Method == "Cash" || exp.Method == "cash" {
			if shift, err := s.Store.GetCurrentShift(r.Context(), outletID); err == nil && shift != nil {
				_ = s.Store.AddShiftExpense(r.Context(), shift.ID, exp.Amount, +1)
				s.publish(r, "shift.updated", outletID, shift)
			}
		}
		return http.StatusCreated, exp, nil
	})
}

func (s *Server) handleDeleteExpense(w http.ResponseWriter, r *http.Request) {
	exp, err := s.Store.DeleteExpense(r.Context(), pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	// Reversal: a deleted cash expense leaves the drawer again.
	if exp.Method == "Cash" || exp.Method == "cash" {
		if shift, err := s.Store.GetCurrentShift(r.Context(), exp.OutletID); err == nil && shift != nil {
			_ = s.Store.AddShiftExpense(r.Context(), shift.ID, exp.Amount, -1)
			s.publish(r, "shift.updated", exp.OutletID, shift)
		}
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"deleted": true})
}

// ---- Customers ----

func (s *Server) handleListCustomers(w http.ResponseWriter, r *http.Request) {
	outletID := outletScope(r)
	if outletID == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_outlet", "outlet_id is required"))
		return
	}
	list, err := s.Store.ListCustomers(r.Context(), outletID, r.URL.Query().Get("q"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"customers": list})
}

func (s *Server) handleCreateCustomer(w http.ResponseWriter, r *http.Request) {
	var req models.CustomerCreate
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	outletID := outletScope(r)
	c, err := s.Store.CreateCustomer(r.Context(), outletID, req)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, c)
}

// ---- Inventory / Suppliers / Purchases ----

func (s *Server) handleListInventory(w http.ResponseWriter, r *http.Request) {
	outletID := outletScope(r)
	if outletID == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_outlet", "outlet_id is required"))
		return
	}
	lowOnly := r.URL.Query().Get("low") == "1"
	list, err := s.Store.ListInventory(r.Context(), outletID, lowOnly)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"inventory": list})
}

func (s *Server) handleCreateInventoryItem(w http.ResponseWriter, r *http.Request) {
	var item models.InventoryItem
	if err := httpx.Decode(r, &item); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	outletID := outletScope(r)
	if item.Name == "" || item.Unit == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_item", "name and unit are required"))
		return
	}
	item.OutletID = outletID
	created, err := s.Store.CreateInventoryItem(r.Context(), outletID, item)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, created)
}

func (s *Server) handleAdjustStock(w http.ResponseWriter, r *http.Request) {
	var req models.StockAdjust
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if req.Reason == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_reason", "An adjustment reason is required (audit)"))
		return
	}
	outletID := outletScope(r)
	claims, _ := claimsFrom(r)
	item, err := s.Store.AdjustStock(r.Context(), outletID, pathID(r, "id"), req.Delta, req.Reason, claims.StaffID, claims.Name)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, item)
}

func (s *Server) handleListSuppliers(w http.ResponseWriter, r *http.Request) {
	outletID := outletScope(r)
	if outletID == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_outlet", "outlet_id is required"))
		return
	}
	list, err := s.Store.ListSuppliers(r.Context(), outletID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"suppliers": list})
}

func (s *Server) handleCreateSupplier(w http.ResponseWriter, r *http.Request) {
	var req models.SupplierCreate
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	outletID := outletScope(r)
	sup, err := s.Store.CreateSupplier(r.Context(), outletID, req)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, sup)
}

func (s *Server) handleListPurchases(w http.ResponseWriter, r *http.Request) {
	outletID := outletScope(r)
	if outletID == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_outlet", "outlet_id is required"))
		return
	}
	list, err := s.Store.ListPurchases(r.Context(), outletID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"purchases": list})
}

func (s *Server) handleCreatePurchase(w http.ResponseWriter, r *http.Request) {
	s.withIdempotency(w, r, func() (int, any, error) {
		var req models.PurchaseCreate
		if err := httpx.Decode(r, &req); err != nil {
			return 0, nil, err
		}
		outletID := outletScope(r)
		if outletID == "" {
			return 0, nil, httpx.NewError(400, "missing_outlet", "outlet_id is required")
		}
		claims, _ := claimsFrom(r)
		p, err := s.Store.CreatePurchase(r.Context(), outletID, req, claims.StaffID, claims.Name)
		if err != nil {
			return 0, nil, err
		}
		return http.StatusCreated, p, nil
	})
}

func (s *Server) handlePatchPurchase(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Status string `json:"status"`
	}
	if err := httpx.Decode(r, &body); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	p, err := s.Store.PatchPurchaseStatus(r.Context(), pathID(r, "id"), body.Status)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, p)
}

func (s *Server) handleListStockLog(w http.ResponseWriter, r *http.Request) {
	outletID := outletScope(r)
	if outletID == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_outlet", "outlet_id is required"))
		return
	}
	list, err := s.Store.ListStockAdjustments(r.Context(), outletID, r.URL.Query().Get("item_id"), queryInt(r, "limit", 100))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"adjustments": list})
}

func (s *Server) handleBookCredit(w http.ResponseWriter, r *http.Request) {
	s.withIdempotency(w, r, func() (int, any, error) {
		var req models.CreditBookReq
		if err := httpx.Decode(r, &req); err != nil {
			return 0, nil, err
		}
		outletID := outletScope(r)
		if outletID == "" {
			return 0, nil, httpx.NewError(400, "missing_outlet", "outlet_id is required")
		}
		claims, _ := claimsFrom(r)
		c, err := s.Store.BookCustomerCredit(r.Context(), outletID, pathID(r, "id"), req.Kind, req.AmountPaise, req.Reason, claims.StaffID, claims.Name)
		if err != nil {
			return 0, nil, err
		}
		return http.StatusOK, c, nil
	})
}

func (s *Server) handleListCreditLog(w http.ResponseWriter, r *http.Request) {
	outletID := outletScope(r)
	if outletID == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_outlet", "outlet_id is required"))
		return
	}
	list, err := s.Store.ListCustomerCreditLog(r.Context(), outletID, pathID(r, "id"), queryInt(r, "limit", 100))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"entries": list})
}

// ---- Reports (all derived from real data — PRD FR-R1..R3) ----

func (s *Server) handleDashboardReport(w http.ResponseWriter, r *http.Request) {
	outletID := outletScope(r)
	if outletID == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_outlet", "outlet_id is required"))
		return
	}
	rep := models.DashboardReport{
		SalesByType:   map[string]int64{},
		SalesByTender: map[string]int64{},
		TopCategories: []models.CategorySales{},
	}

	shift, _ := s.Store.GetCurrentShift(r.Context(), outletID)
	if shift != nil {
		rep.SalesPaise = shift.TotalSales()
		rep.CashDrawerPaise = shift.ExpectedCash()
	}
	completed, err := s.Store.ListOrders(r.Context(), outletID, "completed", 500)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	// Only orders paid during this shift count toward the shift AOV.
	shiftStart := "0000-01-01"
	if shift != nil {
		shiftStart = store.TimeStr(shift.StartedAt)
	}
	var shiftSales int64
	shiftOrders := 0
	revenue := map[string]int64{}
	qty := map[string]int{}
	for i := range completed {
		o := &completed[i]
		if o.PaidAt != nil && store.TimeStr(*o.PaidAt) >= shiftStart {
			shiftOrders++
			shiftSales += o.GrandTotalPaise
		}
		rep.SalesByType[o.Type] += o.GrandTotalPaise
		if o.PaymentMethod != nil {
			rep.SalesByTender[*o.PaymentMethod] += o.GrandTotalPaise
		}
		for _, it := range o.Items {
			if it.IsCancelled {
				continue
			}
			revenue[it.Name] += it.TotalPaise
			qty[it.Name] += it.Quantity
		}
	}
	if shift != nil {
		rep.SalesPaise = shiftSales
	}
	rep.OrderCount = shiftOrders
	if rep.OrderCount > 0 {
		rep.AOVPaise = rep.SalesPaise / int64(rep.OrderCount)
	}
	exp, _ := s.Store.SumExpenses(r.Context(), outletID, "today")
	rep.ExpensesPaise = exp

	tables, _ := s.Store.ListTables(r.Context(), outletID, "")
	for _, t := range tables {
		if t.Status == "available" {
			rep.FreeTables++
		} else if t.Status == "occupied" || t.Status == "billing" {
			rep.OccupiedTables++
		}
	}
	kots, _ := s.Store.ListKOTs(r.Context(), outletID, "")
	for _, k := range kots {
		if k.Status != "served" && k.Status != "cancelled" {
			rep.PendingKOTs++
		}
	}

	// Top categories by item revenue (top 5).
	for name, rev := range revenue {
		rep.TopCategories = append(rep.TopCategories, models.CategorySales{Category: name, Revenue: rev, Quantity: qty[name]})
	}
	for i := 0; i < len(rep.TopCategories); i++ {
		for j := i + 1; j < len(rep.TopCategories); j++ {
			if rep.TopCategories[j].Revenue > rep.TopCategories[i].Revenue {
				rep.TopCategories[i], rep.TopCategories[j] = rep.TopCategories[j], rep.TopCategories[i]
			}
		}
	}
	if len(rep.TopCategories) > 5 {
		rep.TopCategories = rep.TopCategories[:5]
	}
	httpx.JSON(w, http.StatusOK, rep)
}

func (s *Server) handleZReport(w http.ResponseWriter, r *http.Request) {
	shift, err := s.Store.GetShift(r.Context(), pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	z := models.ZReport{
		Shift:        *shift,
		ExpectedCash: shift.ExpectedCash(),
		TotalSales:   shift.TotalSales(),
	}
	if shift.CountedPaise != nil {
		z.CountedCash = *shift.CountedPaise
		z.DifferencePaise = z.CountedCash - z.ExpectedCash
	}
	httpx.JSON(w, http.StatusOK, z)
}

// compile-time guard that the service package is linked in (KOT FSM lives there).
var _ = service.ValidateKOTTransition
var _ = middleware.Auth
