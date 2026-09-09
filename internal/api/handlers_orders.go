package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/models"
	"foodpos/backend/internal/service"
	"foodpos/backend/internal/store"
)

// outletScope resolves the outlet for a request: explicit query param wins,
// otherwise the JWT claim.
func outletScope(r *http.Request) string {
	if v := r.URL.Query().Get("outlet_id"); v != "" {
		return v
	}
	if c, ok := claimsFrom(r); ok && c.OutletID != "" {
		return c.OutletID
	}
	return ""
}

func (s *Server) handleListOrders(w http.ResponseWriter, r *http.Request) {
	outletID := outletScope(r)
	if outletID == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_outlet", "outlet_id is required"))
		return
	}
	orders, err := s.Store.ListOrders(r.Context(), outletID, r.URL.Query().Get("status"), queryInt(r, "limit", 100))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"orders": orders})
}

// withIdempotency replays a stored response for repeated offline writes.
func (s *Server) withIdempotency(w http.ResponseWriter, r *http.Request, produce func() (int, any, error)) {
	key := r.Header.Get("Idempotency-Key")
	if key != "" {
		if code, body, found, err := s.Store.GetIdempotentResponse(r.Context(), key); err == nil && found {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(code)
			_, _ = w.Write(body)
			return
		}
	}
	code, payload, err := produce()
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	body, _ := json.Marshal(payload)
	if key != "" {
		_ = s.Store.SaveIdempotentResponse(r.Context(), key, code, body)
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_, _ = w.Write(body)
}

func (s *Server) handleCreateOrder(w http.ResponseWriter, r *http.Request) {
	s.withIdempotency(w, r, func() (int, any, error) {
		var req models.OrderCreate
		if err := httpx.Decode(r, &req); err != nil {
			return 0, nil, err
		}
		outletID := outletScope(r)
		if outletID == "" {
			return 0, nil, httpx.NewError(400, "missing_outlet", "outlet_id is required")
		}
		switch req.Type {
		case "dine_in", "takeaway", "delivery":
		default:
			return 0, nil, httpx.NewError(400, "invalid_type", "type must be dine_in, takeaway or delivery")
		}
		if req.Type == "dine_in" && req.TableID == nil {
			return 0, nil, httpx.NewError(400, "missing_table", "dine_in orders require table_id")
		}

		// Table occupancy guard (double-billing protection).
		if req.TableID != nil {
			busy, activeOrder, err := s.Store.TableHasActiveOrder(r.Context(), *req.TableID)
			if err != nil {
				return 0, nil, err
			}
			if busy {
				return 0, nil, httpx.NewError(409, "table_occupied",
					fmt.Sprintf("Table already has active order %s", activeOrder))
			}
		}

		claims, _ := claimsFrom(r)
		now := store.Now()
		num, err := s.Store.NextCounter(r.Context(), outletID, "order")
		if err != nil {
			return 0, nil, err
		}
		guests := req.GuestCount
		if guests <= 0 {
			guests = 1
		}

		// Charge defaults come from the outlet's settings (GST percent,
		// packaging/delivery charges), so what the manager configures is what
		// new orders actually bill. An explicit req.TaxPercent still wins.
		taxPercent := 5.0
		var outletSettings *models.Settings
		if st, err := s.Store.GetSettings(r.Context(), outletID); err == nil {
			outletSettings = st
			if st.GSTPercent > 0 {
				taxPercent = st.GSTPercent
			}
		}
		if req.TaxPercent != nil {
			taxPercent = *req.TaxPercent
		}
		var packagingDefault, deliveryDefault int64
		if outletSettings != nil {
			switch req.Type {
			case "takeaway":
				packagingDefault = outletSettings.PackagingPaise
			case "delivery":
				packagingDefault = outletSettings.PackagingPaise
				deliveryDefault = outletSettings.DeliveryPaise
			}
		}

		o := &models.Order{
			ID:              store.NewID("ord"),
			ClientID:        req.ClientID,
			OutletID:        outletID,
			OrderNumber:     fmt.Sprintf("ORD-%d", 1044+num),
			Type:            req.Type,
			Status:          "received",
			TableID:         req.TableID,
			CustomerName:    req.CustomerName,
			CustomerPhone:   req.CustomerPhone,
			DeliveryAddress: req.DeliveryAddress,
			WaiterID:        strPtr(claims.ActorID),
			WaiterName:      strPtr(claims.Name),
			GuestCount:      guests,
			OrderNote:       req.OrderNote,
			TaxPercent:      taxPercent,
			IsTaxInclusive:  outletSettings != nil && outletSettings.IsGSTInclusive,
			PackagingPaise:  packagingDefault,
			DeliveryPaise:   deliveryDefault,
			CreatedAt:       now,
			UpdatedAt:       now,
			Items:           []models.OrderItem{},
		}
		if req.TableID != nil {
			t, err := s.Store.GetTable(r.Context(), *req.TableID)
			if err != nil {
				return 0, nil, err
			}
			o.TableNumber = strPtr(t.TableNumber)
			if t.GuestCount > guests {
				o.GuestCount = t.GuestCount
			}
		}
		if err := s.Store.InsertOrder(r.Context(), o); err != nil {
			return 0, nil, err
		}
		if req.TableID != nil {
			if err := s.Store.UpdateTableForOrder(r.Context(), *req.TableID, o.ID, 0, o.GuestCount); err != nil {
				return 0, nil, err
			}
			s.publish(r, "table.updated", outletID, o)
		}
		s.publish(r, "order.updated", outletID, o)
		return http.StatusCreated, o, nil
	})
}

func (s *Server) handleGetOrder(w http.ResponseWriter, r *http.Request) {
	o, err := s.Store.GetOrder(r.Context(), pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, o)
}

func (s *Server) handlePatchOrder(w http.ResponseWriter, r *http.Request) {
	var p models.OrderPatch
	if err := httpx.Decode(r, &p); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	o, err := s.Store.GetOrder(r.Context(), pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	// Discount/charge validation: negatives rejected; percent is clamped
	// downstream by ApplyBilling (single source of truth).
	for _, v := range []*int64{p.ServicePaise, p.PackagingPaise, p.DiscountPaise} {
		if v != nil && *v < 0 {
			httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_charge", "charges/discounts cannot be negative"))
			return
		}
	}
	// FR-A3: discounts above threshold (20% or ₹500) need a manager PIN.
	if (p.DiscountPercent != nil && *p.DiscountPercent > 20) ||
		(p.DiscountPaise != nil && *p.DiscountPaise > 50000) {
		if err := s.requireManagerPIN(r.Context(), derefStr(p.ManagerPin)); err != nil {
			httpx.ErrorJSON(w, r, err)
			return
		}
	}
	if p.Status != nil {
		switch *p.Status {
		case "received", "preparing", "ready", "served", "billing":
		default:
			httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_status", "Use /pay or /refund to close an order"))
			return
		}
	}
	if err := s.Store.PatchOrder(r.Context(), o.ID, p); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	// Re-run billing math with the new inputs.
	updated, err := s.Store.GetOrder(r.Context(), o.ID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	service.ApplyBilling(updated)
	if err := s.Store.UpdateOrderMoney(r.Context(), updated); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if updated.TableID != nil {
		_, _ = s.Store.DB.Exec(`UPDATE tables SET current_amount = ? WHERE id = ?`, updated.GrandTotalPaise, *updated.TableID)
	}
	final, _ := s.Store.GetOrder(r.Context(), o.ID)
	s.publish(r, "order.updated", updated.OutletID, final)
	httpx.JSON(w, http.StatusOK, final)
}

func (s *Server) handleAddOrderItem(w http.ResponseWriter, r *http.Request) {
	var req models.OrderItemAdd
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if req.Quantity <= 0 {
		req.Quantity = 1
	}
	o, err := s.Store.GetOrder(r.Context(), pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if o.Status == "completed" || o.Status == "cancelled" {
		httpx.ErrorJSON(w, r, httpx.NewError(409, "invalid_state", "Cannot add items to a closed order"))
		return
	}
	menu, err := s.Store.GetMenuItem(r.Context(), req.MenuItemID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	// Resolve variant price.
	var variantPrice int64
	if req.VariantID != nil {
		found := false
		for _, v := range menu.Variants {
			if v.ID == *req.VariantID {
				variantPrice = v.PricePaise
				found = true
				break
			}
		}
		if !found {
			httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_variant", "Variant not on this menu item"))
			return
		}
	}
	// Validate + price modifiers from the menu definition.
	mods := make([]models.OrderModifier, 0, len(req.Modifiers))
	validMods := map[string]models.OrderModifier{}
	for _, g := range menu.ModifierGroups {
		for _, m := range g.Items {
			validMods[m.ID] = models.OrderModifier{ModifierItemID: m.ID, Name: m.Name, PricePaise: m.PricePaise}
		}
	}
	for _, m := range req.Modifiers {
		if def, ok := validMods[m.ModifierItemID]; ok {
			mods = append(mods, def)
		}
	}
	basePrice := menu.PricePaise
	if variantPrice > 0 {
		basePrice = variantPrice
	}
	_ = basePrice
	unit := service.UnitPricePaise(menu.PricePaise, variantPrice, mods)
	it := &models.OrderItem{
		ClientID:   req.ClientID,
		MenuItemID: menu.ID,
		VariantID:  req.VariantID,
		Quantity:   req.Quantity,
		UnitPaise:  unit,
		TotalPaise: unit * int64(req.Quantity),
		Note:       req.Note,
		Modifiers:  mods,
		Name:       menu.Name,
	}
	if err := s.Store.AddOrderItem(r.Context(), o.ID, it, func(order *models.Order) {
		service.ApplyBilling(order)
	}); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	updated, err := s.Store.GetOrder(r.Context(), o.ID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if updated.TableID != nil {
		_, _ = s.Store.DB.Exec(`UPDATE tables SET current_amount = ? WHERE id = ?`, updated.GrandTotalPaise, *updated.TableID)
	}
	s.publish(r, "order.updated", updated.OutletID, updated)
	httpx.JSON(w, http.StatusCreated, updated)
}

func (s *Server) handleCancelOrderItem(w http.ResponseWriter, r *http.Request) {
	var req models.CancelItemReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if req.Reason == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_reason", "A cancellation reason is required (audit)"))
		return
	}
	orderID, itemID := pathID(r, "id"), pathID(r, "itemId")
	// FR-A3: cancelling an item whose KOT already reached the kitchen needs a
	// manager PIN (food is being wasted/voided after the kitchen saw it).
	if target, err := s.Store.GetOrderItem(r.Context(), orderID, itemID); err == nil && target.IsKOTSent {
		if err := s.requireManagerPIN(r.Context(), req.ManagerPin); err != nil {
			httpx.ErrorJSON(w, r, err)
			return
		}
	}
	if err := s.Store.CancelOrderItem(r.Context(), orderID, itemID, req.Reason); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	o, err := s.Store.GetOrder(r.Context(), orderID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	service.ApplyBilling(o)
	if err := s.Store.UpdateOrderMoney(r.Context(), o); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if o.TableID != nil {
		_, _ = s.Store.DB.Exec(`UPDATE tables SET current_amount = ? WHERE id = ?`, o.GrandTotalPaise, *o.TableID)
	}
	s.publish(r, "order.updated", o.OutletID, o)
	httpx.JSON(w, http.StatusOK, o)
}

func (s *Server) handlePatchOrderItem(w http.ResponseWriter, r *http.Request) {
	var req models.OrderItemPatch
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	orderID, itemID := pathID(r, "id"), pathID(r, "itemId")
	o, err := s.Store.GetOrder(r.Context(), orderID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if o.Status == "completed" || o.Status == "cancelled" {
		httpx.ErrorJSON(w, r, httpx.NewError(409, "invalid_state", "Cannot modify items on a closed order"))
		return
	}
	// FR-A3: dropping a KOT-sent line to zero is a kitchen-facing cancellation
	// and needs a manager PIN, same as the explicit cancel endpoint.
	if req.Quantity == 0 {
		if target, err := s.Store.GetOrderItem(r.Context(), orderID, itemID); err == nil && target.IsKOTSent {
			if err := s.requireManagerPIN(r.Context(), derefStr(req.ManagerPin)); err != nil {
				httpx.ErrorJSON(w, r, err)
				return
			}
		}
	}
	if err := s.Store.UpdateOrderItemQuantity(r.Context(), orderID, itemID, req.Quantity); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	o, err = s.Store.GetOrder(r.Context(), orderID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	service.ApplyBilling(o)
	if err := s.Store.UpdateOrderMoney(r.Context(), o); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if o.TableID != nil {
		_, _ = s.Store.DB.Exec(`UPDATE tables SET current_amount = ? WHERE id = ?`, o.GrandTotalPaise, *o.TableID)
	}
	s.publish(r, "order.updated", o.OutletID, o)
	httpx.JSON(w, http.StatusOK, o)
}

// handleFireKOT fires all un-sent, un-cancelled items (FR-K1).
// Idempotent: a replayed request with the same Idempotency-Key returns the
// originally created KOT instead of a 409 nothing_to_fire.
func (s *Server) handleFireKOT(w http.ResponseWriter, r *http.Request) {
	s.withIdempotency(w, r, func() (int, any, error) {
		o, err := s.Store.GetOrder(r.Context(), pathID(r, "id"))
		if err != nil {
			return 0, nil, err
		}
		unsent := []models.OrderItem{}
		for _, it := range o.Items {
			if !it.IsKOTSent && !it.IsCancelled {
				unsent = append(unsent, it)
			}
		}
		if len(unsent) == 0 {
			return 0, nil, httpx.NewError(409, "nothing_to_fire", "No unsent items on this order")
		}
		num, err := s.Store.NextCounter(r.Context(), o.OutletID, "kot")
		if err != nil {
			return 0, nil, err
		}
		kot := &models.KOT{
			ID:          store.NewID("kot"),
			OutletID:    o.OutletID,
			KOTNumber:   fmt.Sprintf("KOT #%d", 1200+num),
			OrderID:     o.ID,
			Status:      "new",
			WaiterID:    o.WaiterID,
			WaiterName:  o.WaiterName,
			TableNumber: o.TableNumber,
			OrderType:   o.Type,
			Note:        o.OrderNote,
			CreatedAt:   store.Now(),
		}
		for _, it := range unsent {
			kot.Items = append(kot.Items, models.KOTItem{OrderItemID: it.ID, Name: it.Name, Quantity: it.Quantity})
		}
		if err := s.Store.InsertKOT(r.Context(), kot); err != nil {
			return 0, nil, err
		}
		ids := make([]string, len(unsent))
		for i, it := range unsent {
			ids[i] = it.ID
		}
		if err := s.Store.MarkItemsKOTSent(r.Context(), ids); err != nil {
			return 0, nil, err
		}
		if o.Status == "received" {
			if err := s.Store.SetOrderStatus(r.Context(), o.ID, "preparing"); err != nil {
				return 0, nil, err
			}
		}
		if o.TableID != nil {
			_, _ = s.Store.DB.Exec(`UPDATE tables SET status = 'occupied', active_order_id = ? WHERE id = ?`, o.ID, *o.TableID)
		}
		created, _ := s.Store.GetKOT(r.Context(), kot.ID)
		s.publish(r, "kot.created", o.OutletID, created)
		s.publish(r, "order.updated", o.OutletID, o)
		return http.StatusCreated, created, nil
	})
}

func (s *Server) handleListKOTs(w http.ResponseWriter, r *http.Request) {
	outletID := outletScope(r)
	if outletID == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_outlet", "outlet_id is required"))
		return
	}
	kots, err := s.Store.ListKOTs(r.Context(), outletID, r.URL.Query().Get("status"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"kots": kots})
}

func (s *Server) handlePatchKOT(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Status string `json:"status"`
	}
	if err := httpx.Decode(r, &body); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	kot, err := s.Store.GetKOT(r.Context(), pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if err := service.ValidateKOTTransition(kot.Status, body.Status); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if err := s.Store.SetKOTStatus(r.Context(), kot.ID, body.Status); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	updated, _ := s.Store.GetKOT(r.Context(), kot.ID)
	s.publish(r, "kot.updated", kot.OutletID, updated)
	httpx.JSON(w, http.StatusOK, updated)
}

// handlePay completes payment, books shift sales, frees the table (FR-P1..P4).
func (s *Server) handlePay(w http.ResponseWriter, r *http.Request) {
	s.withIdempotency(w, r, func() (int, any, error) {
		var req models.PaymentReq
		if err := httpx.Decode(r, &req); err != nil {
			return 0, nil, err
		}
		o, err := s.Store.GetOrder(r.Context(), pathID(r, "id"))
		if err != nil {
			return 0, nil, err
		}
		if err := service.ValidatePayment(o, req); err != nil {
			return 0, nil, err
		}

		received, change := service.ComputeChange(o, req)
		num, err := s.Store.NextCounter(r.Context(), o.OutletID, "invoice")
		if err != nil {
			return 0, nil, err
		}
		invoice := fmt.Sprintf("INV-%d", 1044+num)

		if err := s.Store.CompleteOrderPayment(r.Context(), o, req.Method, invoice, received, change); err != nil {
			return 0, nil, err
		}

		// Book shift sales.
		if shift, err := s.Store.GetCurrentShift(r.Context(), o.OutletID); err == nil && shift != nil {
			_ = s.Store.AddShiftSales(r.Context(), shift.ID, req.Method, o.GrandTotalPaise)
		}
		// Customer rollup.
		if o.CustomerPhone != nil && *o.CustomerPhone != "" {
			name := "Guest"
			if o.CustomerName != nil {
				name = *o.CustomerName
			}
			_ = s.Store.RecordCustomerSpend(r.Context(), o.OutletID, name, *o.CustomerPhone, o.GrandTotalPaise)
		}

		updated, err := s.Store.GetOrder(r.Context(), o.ID)
		if err != nil {
			return 0, nil, err
		}
		s.publish(r, "order.updated", o.OutletID, updated)
		if o.TableID != nil {
			if t, err := s.Store.GetTable(r.Context(), *o.TableID); err == nil {
				s.publish(r, "table.updated", o.OutletID, t)
			}
		}
		return http.StatusOK, updated, nil
	})
}

// handleRefund validates and records a tender-aware refund (FR-P4).
func (s *Server) handleRefund(w http.ResponseWriter, r *http.Request) {
	var req models.RefundReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	o, err := s.Store.GetOrder(r.Context(), pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	// FR-A3: refunds are a manager/admin action — enforced here, not only in UI.
	if err := s.requireManagerPIN(r.Context(), req.ManagerPin); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if err := service.ValidateRefund(o, req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if req.IsFull {
		if err := s.Store.SetOrderStatus(r.Context(), o.ID, "cancelled"); err != nil {
			httpx.ErrorJSON(w, r, err)
			return
		}
	}
	if shift, err := s.Store.GetCurrentShift(r.Context(), o.OutletID); err == nil && shift != nil {
		isCash := service.RefundIsCash(o.PaymentMethod, req.Mode)
		_ = s.Store.AddShiftRefund(r.Context(), shift.ID, isCash, req.AmountPaise)
	}
	updated, err := s.Store.GetOrder(r.Context(), o.ID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	s.publish(r, "order.updated", o.OutletID, updated)
	httpx.JSON(w, http.StatusOK, map[string]any{
		"order":          updated,
		"refunded_paise": req.AmountPaise,
		"mode":           req.Mode,
		"reason":         req.Reason,
		"processed_at":   time.Now().UTC(),
	})
}
