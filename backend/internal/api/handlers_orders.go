package api

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"foodpos/backend/internal/auth"
	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/models"
	"foodpos/backend/internal/service"
	"foodpos/backend/internal/store"
)

// outletScope resolves the outlet for a request. POS routes run behind
// StaffTenant, which already rejects an ?outlet_id that differs from the
// claim, so the claim is authoritative.
func outletScope(r *http.Request) string {
	if c, ok := claimsFrom(r); ok && c.OutletID != "" {
		return c.OutletID
	}
	return r.URL.Query().Get("outlet_id")
}

// sameOutlet reports whether a staff caller may touch a row of outletID.
func sameOutlet(r *http.Request, outletID string) bool {
	c, ok := claimsFrom(r)
	return !ok || c.Scope != auth.ScopeStaff || c.OutletID == outletID
}

// loadOrderForCaller fetches an order the caller's outlet owns (404 otherwise
// — a foreign id is indistinguishable from a missing one).
func (s *Server) loadOrderForCaller(r *http.Request, id string) (*models.Order, error) {
	o, err := s.Store.GetOrder(r.Context(), id)
	if err != nil {
		return nil, err
	}
	if !sameOutlet(r, o.OutletID) {
		return nil, httpx.ErrNotFound
	}
	return o, nil
}

// parseRangeParams resolves ?from/?to: a date-only value is a calendar day in
// the outlet's timezone (to is exclusive of the following midnight, so
// to=2026-10-09 includes the whole 9th); RFC3339 values are used as given.
func parseRangeParams(r *http.Request, loc *time.Location) (from, to *time.Time, err error) {
	return parseRange(r.URL.Query().Get("from"), r.URL.Query().Get("to"), loc)
}

// parseRange is the pure core of parseRangeParams (nil = unbounded).
func parseRange(fromStr, toStr string, loc *time.Location) (from, to *time.Time, err error) {
	parse := func(v string, end bool) (*time.Time, error) {
		if v == "" {
			return nil, nil
		}
		if t, err := time.Parse(time.RFC3339Nano, v); err == nil {
			t = t.UTC()
			return &t, nil
		}
		d, err := time.ParseInLocation("2006-01-02", v, loc)
		if err != nil {
			return nil, httpx.NewError(400, "bad_range", "invalid from/to — use YYYY-MM-DD or RFC3339")
		}
		if end {
			d = d.AddDate(0, 0, 1)
		}
		d = d.UTC()
		return &d, nil
	}
	if from, err = parse(fromStr, false); err != nil {
		return nil, nil, err
	}
	if to, err = parse(toStr, true); err != nil {
		return nil, nil, err
	}
	return from, to, nil
}

func (s *Server) handleListOrders(w http.ResponseWriter, r *http.Request) {
	outletID := outletScope(r)
	if outletID == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_outlet", "outlet_id is required"))
		return
	}
	q := r.URL.Query()
	f := store.OrderFilter{OutletID: outletID, WaiterID: q.Get("waiter_id"), Limit: queryInt(r, "limit", 100)}
	if c, ok := claimsFrom(r); ok && c.Role == "waiter" {
		f.WaiterID = c.ActorID
	}
	for _, st := range strings.Split(q.Get("status"), ",") {
		if st = strings.TrimSpace(st); st != "" {
			f.Statuses = append(f.Statuses, st)
		}
	}
	from, to, err := parseRangeParams(r, s.Store.OutletLocation(r.Context(), outletID))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	f.PaidFrom, f.PaidTo = from, to
	if b := q.Get("before"); b != "" {
		t, err := time.Parse(time.RFC3339Nano, b)
		if err != nil {
			httpx.ErrorJSON(w, r, httpx.NewError(400, "bad_cursor", "before must be an RFC3339 timestamp"))
			return
		}
		f.Before = &t
	}
	orders, err := s.Store.ListOrders(r.Context(), f)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"orders": orders})
}

// withIdempotency makes a write replay-safe for offline retries. The key is
// reserved BEFORE the write runs, so two concurrent duplicates cannot both
// execute (the loser gets 409 in_progress, or the stored response once the
// winner finishes). Keys are namespaced by org, actor, method and path.
// Failures release the reservation so the client may retry.
func (s *Server) withIdempotency(w http.ResponseWriter, r *http.Request, produce func() (int, any, error)) {
	raw := r.Header.Get("Idempotency-Key")
	if raw == "" {
		code, payload, err := produce()
		if err != nil {
			httpx.ErrorJSON(w, r, err)
			return
		}
		httpx.JSON(w, code, payload)
		return
	}
	var org, actor string
	if c, ok := claimsFrom(r); ok {
		org, actor = c.OrgID, c.ActorID
	}
	sum := sha256.Sum256([]byte(org + ":" + actor + ":" + r.Method + ":" + r.URL.Path + ":" + raw))
	key := hex.EncodeToString(sum[:])
	code, body, found, err := s.Store.ReserveIdempotencyKey(r.Context(), key)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if found {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Idempotent-Replay", "true")
		w.WriteHeader(code)
		_, _ = w.Write(body)
		return
	}
	code, payload, err := produce()
	if err != nil {
		_ = s.Store.ReleaseIdempotencyKey(r.Context(), key)
		httpx.ErrorJSON(w, r, err)
		return
	}
	body, _ = json.Marshal(payload)
	if err := s.Store.CompleteIdempotencyKey(r.Context(), key, code, body); err != nil {
		slog.Error("idempotency complete", "err", err)
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_, _ = w.Write(body)
}

// resolveWaiter checks a waiter id belongs to the caller's org and (unless
// org-wide) to outletID, returning their display name.
func (s *Server) resolveWaiter(r *http.Request, waiterID, outletID string) (string, error) {
	st, err := s.Store.GetStaff(r.Context(), waiterID)
	invalid := httpx.NewError(400, "invalid_waiter", "Waiter not found in this outlet")
	if err != nil {
		if errors.Is(err, httpx.ErrNotFound) {
			return "", invalid
		}
		return "", err
	}
	c, _ := claimsFrom(r)
	if c != nil && st.OrgID != c.OrgID {
		return "", invalid
	}
	if st.OutletID != nil && *st.OutletID != "" && *st.OutletID != outletID {
		return "", invalid
	}
	if !st.IsActive {
		return "", invalid
	}
	return st.Name, nil
}

func validPercent(v *float64, max float64) bool { return v == nil || (*v >= 0 && *v <= max) }

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
		if req.Type == "dine_in" && (req.TableID == nil || *req.TableID == "") {
			return 0, nil, httpx.NewError(400, "missing_table", "dine_in orders require table_id")
		}
		if req.TableID != nil && *req.TableID == "" {
			req.TableID = nil
		}
		if !validPercent(req.TaxPercent, 28) {
			return 0, nil, httpx.NewError(400, "invalid_tax", "tax_percent must be between 0 and 28")
		}
		if req.GuestCount < 0 || req.GuestCount > 999 {
			return 0, nil, httpx.NewError(400, "invalid_guests", "guest_count must be between 0 and 999")
		}
		claims, _ := claimsFrom(r)
		now := store.Now()
		guests := req.GuestCount
		if guests <= 0 {
			guests = 1
		}

		// Charge defaults come from the outlet's settings so what the manager
		// configures is what new orders bill. An explicit tax_percent wins.
		taxPercent := 5.0
		var st *models.Settings
		if v, err := s.Store.GetSettings(r.Context(), outletID); err == nil {
			st = v
			if v.GSTPercent > 0 {
				taxPercent = v.GSTPercent
			}
		}
		if req.TaxPercent != nil {
			taxPercent = *req.TaxPercent
		}
		var packaging, delivery int64
		var servicePct float64
		if st != nil {
			switch req.Type {
			case "dine_in":
				servicePct = st.ServicePercent
			case "takeaway":
				packaging = st.PackagingPaise
			case "delivery":
				packaging = st.PackagingPaise
				delivery = st.DeliveryPaise
			}
		}

		waiterID, waiterName := req.WaiterID, req.WaiterName
		if waiterID != nil && *waiterID == "" {
			waiterID = nil
		}
		if claims != nil && claims.Role == "waiter" {
			// A waiter always books orders under their own name.
			waiterID, waiterName = strPtr(claims.ActorID), strPtr(claims.Name)
		} else if waiterID != nil {
			name, err := s.resolveWaiter(r, *waiterID, outletID)
			if err != nil {
				return 0, nil, err
			}
			if waiterName == nil || *waiterName == "" {
				waiterName = &name
			}
		}

		var tableNumber *string
		if req.TableID != nil {
			t, err := s.Store.GetTable(r.Context(), *req.TableID)
			if err != nil || t.OutletID != outletID {
				return 0, nil, httpx.NewError(400, "invalid_table", "Table not found in this outlet")
			}
			tableNumber = strPtr(t.TableNumber)
			if t.GuestCount > guests {
				guests = t.GuestCount
			}
			if waiterID == nil && t.AssignedWaiterID != nil && *t.AssignedWaiterID != "" {
				if name, err := s.resolveWaiter(r, *t.AssignedWaiterID, outletID); err == nil {
					waiterID, waiterName = t.AssignedWaiterID, &name
				}
			}
		}
		if waiterID == nil && claims != nil {
			waiterID, waiterName = strPtr(claims.ActorID), strPtr(claims.Name)
		}

		o := &models.Order{
			ID:              store.NewID("ord"),
			ClientID:        req.ClientID,
			OutletID:        outletID,
			Type:            req.Type,
			Status:          "received",
			TableID:         req.TableID,
			TableNumber:     tableNumber,
			CustomerName:    req.CustomerName,
			CustomerPhone:   req.CustomerPhone,
			DeliveryAddress: req.DeliveryAddress,
			WaiterID:        waiterID,
			WaiterName:      waiterName,
			GuestCount:      guests,
			OrderNote:       req.OrderNote,
			TaxPercent:      taxPercent,
			IsTaxInclusive:  st != nil && st.IsGSTInclusive,
			ServicePercent:  servicePct,
			PackagingPaise:  packaging,
			DeliveryPaise:   delivery,
			CreatedAt:       now,
			UpdatedAt:       now,
			Items:           []models.OrderItem{},
		}
		service.ApplyBilling(o)
		// Numbering, insert and the conditional table claim are one tx; a
		// busy table yields 409 table_occupied without naming the other order.
		if err := s.Store.InsertOrder(r.Context(), o); err != nil {
			return 0, nil, err
		}
		if o.TableID != nil {
			if t, err := s.Store.GetTable(r.Context(), *o.TableID); err == nil {
				s.publish(r, "table.updated", outletID, t)
			}
		}
		s.publish(r, "order.updated", outletID, o)
		s.notifyOutlet(outletID, "New order", "Order "+o.OrderNumber+" was created.",
			map[string]string{"type": "order.created", "order_id": o.ID})
		return http.StatusCreated, o, nil
	})
}

func (s *Server) handleGetOrder(w http.ResponseWriter, r *http.Request) {
	o, err := s.loadOrderForCaller(r, pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, o)
}

// afterOrderWrite publishes the order and its table's running amount.
func (s *Server) afterOrderWrite(r *http.Request, o *models.Order) {
	s.publish(r, "order.updated", o.OutletID, o)
	if o.TableID != nil {
		if t, err := s.Store.GetTable(r.Context(), *o.TableID); err == nil {
			s.publish(r, "table.updated", o.OutletID, t)
		}
	}
}

func (s *Server) handlePatchOrder(w http.ResponseWriter, r *http.Request) {
	var p models.OrderPatch
	if err := httpx.Decode(r, &p); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	o, err := s.loadOrderForCaller(r, pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	for _, v := range []*int64{p.ServicePaise, p.PackagingPaise, p.DeliveryPaise, p.DiscountPaise} {
		if v != nil && *v < 0 {
			httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_charge", "charges/discounts cannot be negative"))
			return
		}
	}
	if !validPercent(p.DiscountPercent, 100) {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_discount", "discount_percent must be between 0 and 100"))
		return
	}
	if !validPercent(p.ServicePercent, 20) {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_service", "service_percent must be between 0 and 20"))
		return
	}
	if p.GuestCount != nil && (*p.GuestCount < 0 || *p.GuestCount > 999) {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_guests", "guest_count must be between 0 and 999"))
		return
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
	if p.WaiterID != nil && *p.WaiterID != "" {
		name, err := s.resolveWaiter(r, *p.WaiterID, o.OutletID)
		if err != nil {
			httpx.ErrorJSON(w, r, err)
			return
		}
		if p.WaiterName == nil || *p.WaiterName == "" {
			p.WaiterName = &name
		}
	}
	updated, err := s.Store.MutateOpenOrder(r.Context(), o.ID, service.ApplyBilling,
		func(tx *sql.Tx, _ *models.Order) error { return store.PatchOrderTx(r.Context(), tx, o.ID, p) })
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	s.afterOrderWrite(r, updated)
	httpx.JSON(w, http.StatusOK, updated)
}

// addItemResponse is the order plus the id of the line just added (the
// offline client maps its local line id to it).
type addItemResponse struct {
	*models.Order
	ItemID string `json:"item_id"`
}

// buildOrderItem validates an add-item request against the live menu and
// snapshots name/variant/veg onto the new line.
func buildOrderItem(menu *models.MenuItem, req models.OrderItemAdd) (*models.OrderItem, error) {
	if menu.IsDeleted || !menu.IsAvailable {
		return nil, httpx.NewError(409, "item_unavailable", "This menu item is not available")
	}
	var variantPrice int64
	var variantName *string
	if req.VariantID != nil && *req.VariantID != "" {
		found := false
		for _, v := range menu.Variants {
			if v.ID == *req.VariantID {
				variantPrice = v.PricePaise
				variantName = strPtr(v.Name)
				found = true
				break
			}
		}
		if !found {
			return nil, httpx.NewError(400, "invalid_variant", "Variant not on this menu item")
		}
	} else {
		req.VariantID = nil
	}
	type modDef struct {
		mod   models.OrderModifier
		group int
	}
	defs := map[string]modDef{}
	for gi, g := range menu.ModifierGroups {
		for _, m := range g.Items {
			defs[m.ID] = modDef{models.OrderModifier{ModifierItemID: m.ID, Name: m.Name, PricePaise: m.PricePaise}, gi}
		}
	}
	perGroup := make([]int, len(menu.ModifierGroups))
	mods := make([]models.OrderModifier, 0, len(req.Modifiers))
	seen := map[string]bool{}
	for _, m := range req.Modifiers {
		def, ok := defs[m.ModifierItemID]
		if !ok {
			return nil, httpx.NewError(400, "invalid_modifier", "Modifier not on this menu item")
		}
		if seen[m.ModifierItemID] {
			continue
		}
		seen[m.ModifierItemID] = true
		perGroup[def.group]++
		mods = append(mods, def.mod) // price/name always from the menu
	}
	for gi, g := range menu.ModifierGroups {
		if g.IsRequired && perGroup[gi] == 0 {
			return nil, httpx.NewError(400, "modifier_required", "Choose an option for "+g.Name)
		}
		if !g.IsMultiSelect && perGroup[gi] > 1 {
			return nil, httpx.NewError(400, "invalid_modifier", "Only one option allowed for "+g.Name)
		}
	}
	unit := service.UnitPricePaise(menu.PricePaise, variantPrice, mods)
	return &models.OrderItem{
		ClientID:    req.ClientID,
		MenuItemID:  menu.ID,
		VariantID:   req.VariantID,
		Quantity:    req.Quantity,
		UnitPaise:   unit,
		TotalPaise:  unit * int64(req.Quantity),
		Note:        req.Note,
		Modifiers:   mods,
		Name:        menu.Name,
		VariantName: variantName,
		IsVeg:       menu.IsVeg,
	}, nil
}

func (s *Server) handleAddOrderItem(w http.ResponseWriter, r *http.Request) {
	s.withIdempotency(w, r, func() (int, any, error) {
		var req models.OrderItemAdd
		if err := httpx.Decode(r, &req); err != nil {
			return 0, nil, err
		}
		if req.Quantity == 0 {
			req.Quantity = 1
		}
		if req.Quantity < 1 || req.Quantity > 999 {
			return 0, nil, httpx.NewError(400, "invalid_quantity", "Quantity must be between 1 and 999")
		}
		o, err := s.loadOrderForCaller(r, pathID(r, "id"))
		if err != nil {
			return 0, nil, err
		}
		menu, err := s.Store.GetMenuItem(r.Context(), req.MenuItemID)
		if err != nil || menu.OutletID != o.OutletID {
			return 0, nil, httpx.NewError(400, "invalid_item", "Menu item not found in this outlet")
		}
		it, err := buildOrderItem(menu, req)
		if err != nil {
			return 0, nil, err
		}
		updated, err := s.Store.MutateOpenOrder(r.Context(), o.ID, service.ApplyBilling,
			func(tx *sql.Tx, _ *models.Order) error { return store.AddOrderItemTx(r.Context(), tx, o.ID, it) })
		if err != nil {
			return 0, nil, err
		}
		s.afterOrderWrite(r, updated)
		return http.StatusCreated, addItemResponse{Order: updated, ItemID: it.ID}, nil
	})
}

func (s *Server) handleCancelOrderItem(w http.ResponseWriter, r *http.Request) {
	var req models.CancelItemReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if strings.TrimSpace(req.Reason) == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_reason", "A cancellation reason is required (audit)"))
		return
	}
	orderID, itemID := pathID(r, "id"), pathID(r, "itemId")
	if _, err := s.loadOrderForCaller(r, orderID); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	o, err := s.Store.MutateOpenOrder(r.Context(), orderID, service.ApplyBilling, func(tx *sql.Tx, cur *models.Order) error {
		for _, it := range cur.Items {
			// FR-A3: voiding a line the kitchen already saw needs a manager PIN.
			if it.ID == itemID && it.IsKOTSent && !it.IsCancelled {
				if err := s.requireManagerPIN(r.Context(), req.ManagerPin); err != nil {
					return err
				}
			}
		}
		return store.CancelOrderItemTx(r.Context(), tx, orderID, itemID, req.Reason)
	})
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	s.afterOrderWrite(r, o)
	httpx.JSON(w, http.StatusOK, o)
}

func (s *Server) handlePatchOrderItem(w http.ResponseWriter, r *http.Request) {
	var req models.OrderItemPatch
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	orderID, itemID := pathID(r, "id"), pathID(r, "itemId")
	if _, err := s.loadOrderForCaller(r, orderID); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	var newItemID string
	o, err := s.Store.MutateOpenOrder(r.Context(), orderID, service.ApplyBilling, func(tx *sql.Tx, cur *models.Order) error {
		for _, it := range cur.Items {
			// FR-A3: lowering a KOT-sent line (incl. to zero) voids food the
			// kitchen already saw → manager PIN, same as the cancel endpoint.
			if it.ID == itemID && it.IsKOTSent && req.Quantity < it.Quantity {
				if err := s.requireManagerPIN(r.Context(), derefStr(req.ManagerPin)); err != nil {
					return err
				}
			}
		}
		var err error
		newItemID, err = store.UpdateOrderItemQuantityTx(r.Context(), tx, cur, itemID, req.Quantity)
		return err
	})
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	s.afterOrderWrite(r, o)
	if newItemID != "" {
		// Qty increase on a fired line added an unsent delta line.
		httpx.JSON(w, http.StatusOK, addItemResponse{Order: o, ItemID: newItemID})
		return
	}
	httpx.JSON(w, http.StatusOK, o)
}

// handleFireKOT fires all un-sent, un-cancelled items (FR-K1) in one
// transaction. Idempotent: a replay returns the originally created KOT.
func (s *Server) handleFireKOT(w http.ResponseWriter, r *http.Request) {
	s.withIdempotency(w, r, func() (int, any, error) {
		o, err := s.loadOrderForCaller(r, pathID(r, "id"))
		if err != nil {
			return 0, nil, err
		}
		kot, err := s.Store.FireKOT(r.Context(), o.ID, func(cur *models.Order, num int) *models.KOT {
			return &models.KOT{
				ID:          store.NewID("kot"),
				OutletID:    cur.OutletID,
				KOTNumber:   fmt.Sprintf("KOT #%d", 1200+num),
				OrderID:     cur.ID,
				Status:      "new",
				WaiterID:    cur.WaiterID,
				WaiterName:  cur.WaiterName,
				TableNumber: cur.TableNumber,
				OrderType:   cur.Type,
				Note:        cur.OrderNote,
				CreatedAt:   store.Now(),
			}
		})
		if err != nil {
			return 0, nil, err
		}
		s.publish(r, "kot.created", o.OutletID, kot)
		if fresh, err := s.Store.GetOrder(r.Context(), o.ID); err == nil {
			s.afterOrderWrite(r, fresh)
		}
		return http.StatusCreated, kot, nil
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
	var body models.KOTStatusPatch
	if err := httpx.Decode(r, &body); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	kot, err := s.Store.GetKOT(r.Context(), pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if !sameOutlet(r, kot.OutletID) {
		httpx.ErrorJSON(w, r, httpx.ErrNotFound)
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
	updated, err := s.Store.GetKOT(r.Context(), kot.ID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	s.publish(r, "kot.updated", kot.OutletID, updated)
	if body.Status == "ready" {
		where := ""
		if updated.TableNumber != nil {
			where = " for table " + *updated.TableNumber
		}
		s.notifyOutlet(kot.OutletID, "Order ready", updated.KOTNumber+" is ready"+where+".",
			map[string]string{"type": "kot.ready", "kot_id": kot.ID, "order_id": kot.OrderID})
	}
	httpx.JSON(w, http.StatusOK, updated)
}

// handlePay settles an order (FR-P1..P4) in one transaction: status guard
// (409 already_paid on a second pay), invoice number, tender legs into the
// open shift (409 shift_required without one), credit booking, customer
// rollup and table release.
func (s *Server) handlePay(w http.ResponseWriter, r *http.Request) {
	s.withIdempotency(w, r, func() (int, any, error) {
		var req models.PaymentReq
		if err := httpx.Decode(r, &req); err != nil {
			return 0, nil, err
		}
		o, err := s.loadOrderForCaller(r, pathID(r, "id"))
		if err != nil {
			return 0, nil, err
		}
		plan, err := service.PlanPayment(o, req)
		if err != nil {
			return 0, nil, err
		}
		if req.CustomerID != nil && *req.CustomerID == "" {
			req.CustomerID = nil
		}
		claims, _ := claimsFrom(r)
		in := store.PayInput{
			OrderID: o.ID, ExpectedTotal: o.GrandTotalPaise, Method: req.Method, Legs: plan.Legs,
			Received: plan.Received, Change: plan.Change, Reference: req.Reference, CustomerID: req.CustomerID,
		}
		if in.Method == "" && len(req.Splits) > 0 {
			in.Method = "split"
		}
		if in.Method == "credit" {
			in.Received = o.GrandTotalPaise
		}
		if claims != nil {
			in.StaffID, in.StaffName = claims.ActorID, claims.Name
		}
		if err := s.Store.PayOrder(r.Context(), in); err != nil {
			return 0, nil, err
		}
		updated, err := s.Store.GetOrder(r.Context(), o.ID)
		if err != nil {
			return 0, nil, err
		}
		s.afterOrderWrite(r, updated)
		if sh, err := s.Store.GetCurrentShift(r.Context(), o.OutletID); err == nil && sh != nil {
			s.publish(r, "shift.updated", o.OutletID, sh)
		}
		return http.StatusOK, updated, nil
	})
}

// handleRefund records a tender-aware refund (FR-P4) against the refund
// ledger: capped at grand total − refunded, full refund flips the order to
// 'refunded', replays are idempotent.
func (s *Server) handleRefund(w http.ResponseWriter, r *http.Request) {
	s.withIdempotency(w, r, func() (int, any, error) {
		var req models.RefundReq
		if err := httpx.Decode(r, &req); err != nil {
			return 0, nil, err
		}
		o, err := s.loadOrderForCaller(r, pathID(r, "id"))
		if err != nil {
			return 0, nil, err
		}
		// FR-A3: refunds are a manager/admin action — enforced here, not only in UI.
		if err := s.requireManagerPIN(r.Context(), req.ManagerPin); err != nil {
			return 0, nil, err
		}
		if err := service.ValidateRefund(o, req); err != nil {
			return 0, nil, err
		}
		mode := req.Mode
		if mode == "" {
			mode = "original"
		}
		isCreditSale := o.PaymentMethod != nil && *o.PaymentMethod == "credit"
		claims, _ := claimsFrom(r)
		in := store.RefundInput{
			OrderID: o.ID, Amount: req.AmountPaise, IsFull: req.IsFull, Mode: mode, Reason: req.Reason,
			IsCash:     !isCreditSale && service.RefundIsCash(o.PaymentMethod, mode),
			CreditNote: isCreditSale && mode == "original",
		}
		if claims != nil {
			in.StaffID, in.StaffName = claims.ActorID, claims.Name
		}
		ref, err := s.Store.RefundOrder(r.Context(), in)
		if err != nil {
			return 0, nil, err
		}
		updated, err := s.Store.GetOrder(r.Context(), o.ID)
		if err != nil {
			return 0, nil, err
		}
		s.publish(r, "order.updated", o.OutletID, updated)
		if sh, err := s.Store.GetCurrentShift(r.Context(), o.OutletID); err == nil && sh != nil {
			s.publish(r, "shift.updated", o.OutletID, sh)
		}
		return http.StatusOK, map[string]any{
			"order":          updated,
			"refund":         ref,
			"refunded_paise": ref.Amount,
			"mode":           ref.Mode,
			"reason":         ref.Reason,
			"processed_at":   ref.Ts,
		}, nil
	})
}
