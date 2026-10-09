package api

import (
	"net/http"
	"time"

	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/models"
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
		shift, err := s.Store.OpenShift(r.Context(), outletID, claims.ActorID, claims.Name, req)
		if err != nil {
			return 0, nil, err
		}
		s.publish(r, "shift.updated", outletID, shift)
		return http.StatusCreated, shift, nil
	})
}

func (s *Server) handleCloseShift(w http.ResponseWriter, r *http.Request) {
	s.withIdempotency(w, r, func() (int, any, error) {
		var req models.ShiftCloseReq
		if err := httpx.Decode(r, &req); err != nil {
			return 0, nil, err
		}
		if req.CountedPaise < 0 {
			return 0, nil, httpx.ErrInvalidAmount
		}
		outletID := outletScope(r)
		shift, err := s.Store.GetCurrentShift(r.Context(), outletID)
		if err != nil {
			return 0, nil, err
		}
		if shift == nil {
			return 0, nil, httpx.NewError(409, "no_open_shift", "No open shift to close")
		}
		closed, err := s.Store.CloseShift(r.Context(), shift.ID, req)
		if err != nil {
			return 0, nil, err
		}
		s.publish(r, "shift.updated", outletID, closed)
		return http.StatusOK, closed, nil
	})
}

func (s *Server) handleCashMove(w http.ResponseWriter, r *http.Request) {
	s.withIdempotency(w, r, func() (int, any, error) {
		var req models.CashMoveReq
		if err := httpx.Decode(r, &req); err != nil {
			return 0, nil, err
		}
		if req.Amount <= 0 {
			return 0, nil, httpx.ErrInvalidAmount
		}
		if req.Type != "cash_in" && req.Type != "cash_out" {
			return 0, nil, httpx.NewError(400, "invalid_type", "type must be cash_in or cash_out")
		}
		outletID := outletScope(r)
		claims, _ := claimsFrom(r)
		// Shift lookup, drawer check and booking run under one row lock.
		tx, err := s.Store.AddCashMove(r.Context(), outletID, claims.ActorID, claims.Name, req.Type, req.Amount, req.Reason, req.Reference, req.At)
		if err != nil {
			return 0, nil, err
		}
		if updated, err := s.Store.GetShift(r.Context(), tx.ShiftID); err == nil {
			s.publish(r, "shift.updated", outletID, updated)
		}
		return http.StatusCreated, tx, nil
	})
}

// ---- Expenses ----

// expenseWindow resolves ?from/?to (outlet-tz days) or the legacy
// ?range=today|month shortcut.
func (s *Server) expenseWindow(r *http.Request, outletID string) (*time.Time, *time.Time, error) {
	loc := s.Store.OutletLocation(r.Context(), outletID)
	switch r.URL.Query().Get("range") {
	case "today":
		from, to := dayBounds(time.Now(), loc)
		return &from, &to, nil
	case "month":
		now := time.Now().In(loc)
		from := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, loc).UTC()
		to := time.Date(now.Year(), now.Month()+1, 1, 0, 0, 0, 0, loc).UTC()
		return &from, &to, nil
	}
	return parseRangeParams(r, loc)
}

func (s *Server) handleListExpenses(w http.ResponseWriter, r *http.Request) {
	outletID := outletScope(r)
	if outletID == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_outlet", "outlet_id is required"))
		return
	}
	from, to, err := s.expenseWindow(r, outletID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	list, err := s.Store.ListExpenses(r.Context(), outletID, from, to)
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
		// A cash expense is booked onto the open shift in the same tx.
		exp, shiftID, err := s.Store.CreateExpense(r.Context(), outletID, req, strPtr(claims.ActorID))
		if err != nil {
			return 0, nil, err
		}
		if shiftID != "" {
			if sh, err := s.Store.GetShift(r.Context(), shiftID); err == nil {
				s.publish(r, "shift.updated", outletID, sh)
			}
		}
		return http.StatusCreated, exp, nil
	})
}

func (s *Server) handleDeleteExpense(w http.ResponseWriter, r *http.Request) {
	exp, err := s.Store.GetExpense(r.Context(), pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if !sameOutlet(r, exp.OutletID) {
		httpx.ErrorJSON(w, r, httpx.ErrNotFound)
		return
	}
	// The reversal hits the expense's OWN shift, not whichever is open now.
	_, shiftID, err := s.Store.DeleteExpense(r.Context(), exp.ID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if shiftID != "" {
		if sh, err := s.Store.GetShift(r.Context(), shiftID); err == nil {
			s.publish(r, "shift.updated", exp.OutletID, sh)
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
	s.withIdempotency(w, r, func() (int, any, error) {
		var req models.CustomerCreate
		if err := httpx.Decode(r, &req); err != nil {
			return 0, nil, err
		}
		c, err := s.Store.CreateCustomer(r.Context(), outletScope(r), req)
		if err != nil {
			return 0, nil, err
		}
		return http.StatusCreated, c, nil
	})
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
	s.withIdempotency(w, r, func() (int, any, error) {
		var item models.InventoryItem
		if err := httpx.Decode(r, &item); err != nil {
			return 0, nil, err
		}
		outletID := outletScope(r)
		if item.Name == "" || item.Unit == "" {
			return 0, nil, httpx.NewError(400, "invalid_item", "name and unit are required")
		}
		if item.Stock < 0 || item.MinStock < 0 || item.CostPaise < 0 {
			return 0, nil, httpx.NewError(400, "invalid_item", "stock, min_stock and cost cannot be negative")
		}
		item.OutletID = outletID
		created, err := s.Store.CreateInventoryItem(r.Context(), outletID, item)
		if err != nil {
			return 0, nil, err
		}
		return http.StatusCreated, created, nil
	})
}

func (s *Server) handleAdjustStock(w http.ResponseWriter, r *http.Request) {
	s.withIdempotency(w, r, func() (int, any, error) {
		var req models.StockAdjust
		if err := httpx.Decode(r, &req); err != nil {
			return 0, nil, err
		}
		if req.Reason == "" {
			return 0, nil, httpx.NewError(400, "missing_reason", "An adjustment reason is required (audit)")
		}
		claims, _ := claimsFrom(r)
		item, err := s.Store.AdjustStock(r.Context(), outletScope(r), pathID(r, "id"), req.Delta, req.Reason, claims.ActorID, claims.Name)
		if err != nil {
			return 0, nil, err
		}
		return http.StatusOK, item, nil
	})
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
	s.withIdempotency(w, r, func() (int, any, error) {
		var req models.SupplierCreate
		if err := httpx.Decode(r, &req); err != nil {
			return 0, nil, err
		}
		sup, err := s.Store.CreateSupplier(r.Context(), outletScope(r), req)
		if err != nil {
			return 0, nil, err
		}
		return http.StatusCreated, sup, nil
	})
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
		p, err := s.Store.CreatePurchase(r.Context(), outletID, req, claims.ActorID, claims.Name)
		if err != nil {
			return 0, nil, err
		}
		return http.StatusCreated, p, nil
	})
}

func (s *Server) handlePatchPurchase(w http.ResponseWriter, r *http.Request) {
	var body models.PurchasePatch
	if err := httpx.Decode(r, &body); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	existing, err := s.Store.GetPurchase(r.Context(), pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if !sameOutlet(r, existing.OutletID) {
		httpx.ErrorJSON(w, r, httpx.ErrNotFound)
		return
	}
	if body.Status != "paid" && body.Status != "pending" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_status", "status must be paid or pending"))
		return
	}
	p, err := s.Store.PatchPurchaseStatus(r.Context(), existing.ID, body.Status)
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
		c, err := s.Store.BookCustomerCredit(r.Context(), outletID, pathID(r, "id"), req.Kind, req.AmountPaise, req.Reason, claims.ActorID, claims.Name)
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

// dayBounds returns [local midnight, next local midnight) of t's day in loc,
// as UTC instants.
func dayBounds(t time.Time, loc *time.Location) (time.Time, time.Time) {
	lt := t.In(loc)
	start := time.Date(lt.Year(), lt.Month(), lt.Day(), 0, 0, 0, 0, loc)
	return start.UTC(), start.AddDate(0, 0, 1).UTC()
}

// handleDashboardReport aggregates orders paid in [from, to) — date-only
// bounds are outlet-timezone days (to includes its whole day); no range means
// today in the outlet's timezone. All sums run in SQL.
func (s *Server) handleDashboardReport(w http.ResponseWriter, r *http.Request) {
	outletID := outletScope(r)
	if outletID == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_outlet", "outlet_id is required"))
		return
	}
	loc := s.Store.OutletLocation(r.Context(), outletID)
	fromP, toP, err := parseRangeParams(r, loc)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	from, to := dayBounds(time.Now(), loc)
	if fromP != nil || toP != nil {
		from, to = time.Unix(0, 0).UTC(), time.Now().UTC().Add(time.Second)
		if fromP != nil {
			from = *fromP
		}
		if toP != nil {
			to = *toP
		}
	}
	rep := models.DashboardReport{
		SalesByType:        map[string]int64{},
		SalesByTender:      map[string]int64{},
		TopCategories:      []models.CategorySales{},
		TopItems:           []models.ItemSales{},
		StaffSales:         []models.StaffSales{},
		ExpensesByCategory: map[string]int64{},
		From:               from,
		To:                 to,
	}
	if err := s.Store.FillDashboard(r.Context(), outletID, from, to, &rep); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if shift, _ := s.Store.GetCurrentShift(r.Context(), outletID); shift != nil {
		rep.CashDrawerPaise = shift.ExpectedCash()
	}
	tables, err := s.Store.ListTables(r.Context(), outletID, "")
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	for _, t := range tables {
		if t.Status == "available" {
			rep.FreeTables++
		} else if t.Status == "occupied" || t.Status == "billing" {
			rep.OccupiedTables++
		}
	}
	httpx.JSON(w, http.StatusOK, rep)
}

func (s *Server) handleZReport(w http.ResponseWriter, r *http.Request) {
	shift, err := s.Store.GetShift(r.Context(), pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if !sameOutlet(r, shift.OutletID) {
		httpx.ErrorJSON(w, r, httpx.ErrNotFound)
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
