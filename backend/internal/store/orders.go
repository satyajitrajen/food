package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/lib/pq"

	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/models"
)

// Closed orders are immutable: no edits, items, KOTs, or second payment.
var (
	ErrOrderClosed   = httpx.NewError(409, "invalid_state", "Order is closed and can no longer be modified")
	ErrAlreadyPaid   = httpx.NewError(409, "already_paid", "Order is already paid or closed")
	ErrShiftRequired = httpx.NewError(409, "shift_required", "Open a shift before taking payments")
	ErrOrderChanged  = httpx.NewError(409, "order_changed", "Order total changed; refresh and retry")
)

// IsClosedStatus reports whether an order status is terminal.
func IsClosedStatus(st string) bool {
	return st == "completed" || st == "cancelled" || st == "refunded"
}

// ---- Orders ----

const orderCols = `id, client_id, outlet_id, order_number, type, status, table_id, table_number,
	customer_name, customer_phone, delivery_address, waiter_id, waiter_name, guest_count, order_note,
	subtotal_paise, discount_percent, discount_paise, discount_reason, tax_percent, is_tax_inclusive, tax_paise,
	service_paise, service_percent, packaging_paise, delivery_paise, grand_total_paise, invoice_number, paid_at,
	payment_method, payment_reference, customer_id, paid_paise, change_paise, refunded_paise, idempotency_key,
	created_at, updated_at`

func scanOrder(sc interface{ Scan(...any) error }) (*models.Order, error) {
	o := &models.Order{}
	var tableID, tableNumber, custName, custPhone, addr, waiterID, waiterName, note, discountReason,
		invoice, paidAt, method, ref, customerID, idemKey, clientID sql.NullString
	var createdAt, updatedAt string
	var inclusive int
	if err := sc.Scan(&o.ID, &clientID, &o.OutletID, &o.OrderNumber, &o.Type, &o.Status, &tableID, &tableNumber,
		&custName, &custPhone, &addr, &waiterID, &waiterName, &o.GuestCount, &note,
		&o.SubtotalPaise, &o.DiscountPercent, &o.DiscountPaise, &discountReason, &o.TaxPercent, &inclusive, &o.TaxPaise,
		&o.ServicePaise, &o.ServicePercent, &o.PackagingPaise, &o.DeliveryPaise, &o.GrandTotalPaise, &invoice, &paidAt,
		&method, &ref, &customerID, &o.PaidPaise, &o.ChangePaise, &o.RefundedPaise, &idemKey,
		&createdAt, &updatedAt); err != nil {
		return nil, err
	}
	o.IsTaxInclusive = inclusive == 1
	o.ClientID = copyNull(clientID)
	o.TableID = copyNull(tableID)
	o.TableNumber = copyNull(tableNumber)
	o.CustomerName = copyNull(custName)
	o.CustomerPhone = copyNull(custPhone)
	o.DeliveryAddress = copyNull(addr)
	o.WaiterID = copyNull(waiterID)
	o.WaiterName = copyNull(waiterName)
	o.OrderNote = copyNull(note)
	o.DiscountReason = copyNull(discountReason)
	o.InvoiceNumber = copyNull(invoice)
	o.PaymentMethod = copyNull(method)
	o.PaymentRef = copyNull(ref)
	o.CustomerID = copyNull(customerID)
	o.IdempotencyKey = copyNull(idemKey)
	if paidAt.Valid && paidAt.String != "" {
		t := ParseTime(paidAt.String)
		o.PaidAt = &t
	}
	o.CreatedAt = ParseTime(createdAt)
	o.UpdatedAt = ParseTime(updatedAt)
	o.Items = []models.OrderItem{}
	return o, nil
}

func copyNull(n sql.NullString) *string {
	if n.Valid {
		return &n.String
	}
	return nil
}

func (s *Store) GetOrder(ctx context.Context, id string) (*models.Order, error) {
	return s.getOrderQ(ctx, s.DB, id, false)
}

// getOrderQ loads an order + its items through q; forUpdate row-locks the
// order (callers must pass a *sql.Tx then).
func (s *Store) getOrderQ(ctx context.Context, q Querier, id string, forUpdate bool) (*models.Order, error) {
	query := `SELECT ` + orderCols + ` FROM orders WHERE id = ?`
	if forUpdate {
		query += ` FOR UPDATE`
	}
	o, err := scanOrder(q.QueryRowContext(ctx, query, id))
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	items, err := loadOrderItems(ctx, q, []string{id})
	if err != nil {
		return nil, err
	}
	if its, ok := items[id]; ok {
		o.Items = its
	}
	pays, err := loadOrderPayments(ctx, q, []string{id})
	if err != nil {
		return nil, err
	}
	o.Payments = pays[id]
	return o, nil
}

// loadOrderPayments batch-loads the tender legs of the given orders.
// order_payments has no ordering column, so rows come back ordered by id —
// stable across refetches, but not insertion order (cosmetic for split
// receipts only).
func loadOrderPayments(ctx context.Context, q Querier, orderIDs []string) (map[string][]models.PaymentSplit, error) {
	out := map[string][]models.PaymentSplit{}
	if len(orderIDs) == 0 {
		return out, nil
	}
	rows, err := q.QueryContext(ctx, `SELECT order_id, method, amount_paise FROM order_payments
		WHERE order_id = ANY(?) ORDER BY id`, pq.Array(orderIDs))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var orderID string
		var p models.PaymentSplit
		if err := rows.Scan(&orderID, &p.Method, &p.Paise); err != nil {
			return nil, err
		}
		out[orderID] = append(out[orderID], p)
	}
	return out, rows.Err()
}

// GetOrderItem fetches a single order line (used for FR-A3 manager gates).
func (s *Store) GetOrderItem(ctx context.Context, orderID, itemID string) (*models.OrderItem, error) {
	items, err := s.ListOrderItems(ctx, orderID)
	if err != nil {
		return nil, err
	}
	for i := range items {
		if items[i].ID == itemID {
			return &items[i], nil
		}
	}
	return nil, httpx.ErrNotFound
}

func (s *Store) ListOrderItems(ctx context.Context, orderID string) ([]models.OrderItem, error) {
	m, err := loadOrderItems(ctx, s.DB, []string{orderID})
	if err != nil {
		return nil, err
	}
	if its, ok := m[orderID]; ok {
		return its, nil
	}
	return []models.OrderItem{}, nil
}

// loadOrderItems batch-loads the lines (+ modifiers) of the given orders:
// two scoped queries regardless of how many orders are asked for. Reads
// prefer the line snapshot and fall back to the menu for pre-016 rows.
func loadOrderItems(ctx context.Context, q Querier, orderIDs []string) (map[string][]models.OrderItem, error) {
	out := map[string][]models.OrderItem{}
	if len(orderIDs) == 0 {
		return out, nil
	}
	rows, err := q.QueryContext(ctx, `SELECT oi.id, oi.order_id, oi.client_id, oi.menu_item_id, oi.variant_id, oi.quantity,
		oi.unit_paise, oi.total_paise, oi.note, oi.is_kot_sent, oi.is_cancelled, oi.cancel_reason,
		COALESCE(oi.name, mi.name, ''), COALESCE(oi.variant_name, pv.name), COALESCE(oi.is_veg, mi.is_veg, 1)
		FROM order_items oi
		LEFT JOIN menu_items mi ON mi.id = oi.menu_item_id
		LEFT JOIN product_variants pv ON pv.id = oi.variant_id
		WHERE oi.order_id = ANY(?) ORDER BY oi.seq`, pq.Array(orderIDs))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	owner := map[string]string{} // item id → order id
	pos := map[string]int{}      // item id → index within its order's slice
	var itemIDs []string
	for rows.Next() {
		var it models.OrderItem
		var orderID string
		var variant, note, reason, clientID, variantName sql.NullString
		var kot, cancelled, veg int
		if err := rows.Scan(&it.ID, &orderID, &clientID, &it.MenuItemID, &variant, &it.Quantity, &it.UnitPaise,
			&it.TotalPaise, &note, &kot, &cancelled, &reason, &it.Name, &variantName, &veg); err != nil {
			return nil, err
		}
		it.ClientID = copyNull(clientID)
		it.VariantID = copyNull(variant)
		it.VariantName = nullIfEmpty(variantName)
		it.Note = nullIfEmpty(note)
		it.IsKOTSent = kot == 1
		it.IsCancelled = cancelled == 1
		it.IsVeg = veg == 1
		it.CancelReason = nullIfEmpty(reason)
		it.Modifiers = []models.OrderModifier{}
		out[orderID] = append(out[orderID], it)
		owner[it.ID] = orderID
		pos[it.ID] = len(out[orderID]) - 1
		itemIDs = append(itemIDs, it.ID)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	rows.Close()
	if len(itemIDs) == 0 {
		return out, nil
	}
	mrows, err := q.QueryContext(ctx, `SELECT order_item_id, modifier_item_id, name, price_paise
		FROM order_item_modifiers WHERE order_item_id = ANY(?) ORDER BY seq`, pq.Array(itemIDs))
	if err != nil {
		return nil, err
	}
	defer mrows.Close()
	for mrows.Next() {
		var itemID string
		var m models.OrderModifier
		if err := mrows.Scan(&itemID, &m.ModifierItemID, &m.Name, &m.PricePaise); err != nil {
			return nil, err
		}
		oid, ok := owner[itemID]
		if !ok {
			continue
		}
		out[oid][pos[itemID]].Modifiers = append(out[oid][pos[itemID]].Modifiers, m)
	}
	return out, mrows.Err()
}

func nullIfEmpty(n sql.NullString) *string {
	if n.Valid && n.String != "" {
		return &n.String
	}
	return nil
}

// OrderFilter scopes GET /orders.
type OrderFilter struct {
	OutletID string
	Statuses []string // exact statuses; "running" expands to every open one
	WaiterID string
	PaidFrom *time.Time // paid_at >= PaidFrom
	PaidTo   *time.Time // paid_at <  PaidTo
	Before   *time.Time // created_at < Before (keyset pagination cursor)
	Limit    int
}

func (s *Store) ListOrders(ctx context.Context, f OrderFilter) ([]models.Order, error) {
	q := `SELECT ` + orderCols + ` FROM orders WHERE outlet_id = ?`
	args := []any{f.OutletID}
	var exact []string
	for _, st := range f.Statuses {
		if st == "running" {
			q += ` AND status NOT IN ('completed','cancelled','refunded')`
			continue
		}
		exact = append(exact, st)
	}
	if len(exact) > 0 {
		q += ` AND status = ANY(?)`
		args = append(args, pq.Array(exact))
	}
	if f.WaiterID != "" {
		q += ` AND waiter_id = ?`
		args = append(args, f.WaiterID)
	}
	if f.PaidFrom != nil {
		q += ` AND paid_at >= ?`
		args = append(args, TimeStr(*f.PaidFrom))
	}
	if f.PaidTo != nil {
		q += ` AND paid_at < ?`
		args = append(args, TimeStr(*f.PaidTo))
	}
	if f.Before != nil {
		q += ` AND created_at < ?`
		args = append(args, TimeStr(*f.Before))
	}
	limit := f.Limit
	if limit < 1 {
		limit = 1
	}
	if limit > 500 {
		limit = 500
	}
	q += ` ORDER BY created_at DESC LIMIT ?`
	args = append(args, limit)
	rows, err := s.DB.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []models.Order{}
	var ids []string
	for rows.Next() {
		o, err := scanOrder(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *o)
		ids = append(ids, o.ID)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	rows.Close()
	items, err := loadOrderItems(ctx, s.DB, ids)
	if err != nil {
		return nil, err
	}
	for i := range out {
		if its, ok := items[out[i].ID]; ok {
			out[i].Items = its
		}
	}
	return out, nil
}

// InsertOrder numbers the order, inserts it and — for dine-in — claims the
// table, all in one transaction. The claim is a conditional UPDATE, so two
// terminals racing for the same free table cannot both win.
func (s *Store) InsertOrder(ctx context.Context, o *models.Order) error {
	return s.withTx(ctx, func(tx *sql.Tx) error {
		if o.TableID != nil {
			res, err := tx.ExecContext(ctx, `UPDATE tables SET status = 'occupied', active_order_id = ?,
				current_amount = 0, guest_count = ? WHERE id = ? AND outlet_id = ?
				AND (active_order_id IS NULL OR active_order_id = '')`, o.ID, o.GuestCount, *o.TableID, o.OutletID)
			if err != nil {
				return err
			}
			if n, _ := res.RowsAffected(); n == 0 {
				return httpx.ErrTableOccupied
			}
		}
		num, err := s.NextCounter(ctx, tx, o.OutletID, "order")
		if err != nil {
			return err
		}
		// Display numbering keeps the historical offset (existing outlets
		// already printed these numbers).
		o.OrderNumber = fmt.Sprintf("ORD-%d", 1044+num)
		_, err = tx.ExecContext(ctx, `INSERT INTO orders (id, client_id, outlet_id, order_number, type, status, table_id, table_number,
			customer_name, customer_phone, delivery_address, waiter_id, waiter_name, guest_count, order_note,
			subtotal_paise, discount_percent, discount_paise, discount_reason, tax_percent, is_tax_inclusive, tax_paise,
			service_paise, service_percent, packaging_paise, delivery_paise, grand_total_paise, idempotency_key, created_at, updated_at)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			o.ID, o.ClientID, o.OutletID, o.OrderNumber, o.Type, o.Status, o.TableID, o.TableNumber,
			o.CustomerName, o.CustomerPhone, o.DeliveryAddress, o.WaiterID, o.WaiterName, o.GuestCount, o.OrderNote,
			o.SubtotalPaise, o.DiscountPercent, o.DiscountPaise, o.DiscountReason, o.TaxPercent, b2i(o.IsTaxInclusive), o.TaxPaise,
			o.ServicePaise, o.ServicePercent, o.PackagingPaise, o.DeliveryPaise, o.GrandTotalPaise, o.IdempotencyKey,
			TimeStr(o.CreatedAt), TimeStr(o.UpdatedAt))
		if err != nil {
			return err
		}
		for i := range o.Items {
			if err := insertOrderItemTx(ctx, tx, o.ID, &o.Items[i]); err != nil {
				return err
			}
		}
		return nil
	})
}

func insertOrderItemTx(ctx context.Context, q Querier, orderID string, it *models.OrderItem) error {
	if it.ID == "" {
		it.ID = NewID("oi")
	}
	_, err := q.ExecContext(ctx, `INSERT INTO order_items (id, client_id, order_id, menu_item_id, variant_id, quantity,
		unit_paise, total_paise, note, is_kot_sent, is_cancelled, cancel_reason, name, variant_name, is_veg)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		it.ID, it.ClientID, orderID, it.MenuItemID, it.VariantID, it.Quantity, it.UnitPaise, it.TotalPaise,
		it.Note, b2i(it.IsKOTSent), b2i(it.IsCancelled), it.CancelReason, it.Name, it.VariantName, b2i(it.IsVeg))
	if err != nil {
		return err
	}
	for _, m := range it.Modifiers {
		if _, err := q.ExecContext(ctx,
			`INSERT INTO order_item_modifiers (order_item_id, modifier_item_id, name, price_paise) VALUES (?, ?, ?, ?)`,
			it.ID, m.ModifierItemID, m.Name, m.PricePaise); err != nil {
			return err
		}
	}
	return nil
}

// MutateOpenOrder is the single write path for open-order edits (patch,
// add/qty/cancel item): it row-locks the order, refuses closed orders, runs
// fn inside the transaction, re-reads the lines, re-applies billing via
// recompute and stores money + the table's running amount atomically.
func (s *Store) MutateOpenOrder(ctx context.Context, orderID string, recompute func(*models.Order),
	fn func(tx *sql.Tx, o *models.Order) error) (*models.Order, error) {
	var out *models.Order
	err := s.withTx(ctx, func(tx *sql.Tx) error {
		o, err := s.getOrderQ(ctx, tx, orderID, true)
		if err != nil {
			return err
		}
		if IsClosedStatus(o.Status) {
			return ErrOrderClosed
		}
		if err := fn(tx, o); err != nil {
			return err
		}
		fresh, err := s.getOrderQ(ctx, tx, orderID, false)
		if err != nil {
			return err
		}
		recompute(fresh)
		if err := updateOrderMoney(ctx, tx, fresh); err != nil {
			return err
		}
		if fresh.TableID != nil {
			if _, err := tx.ExecContext(ctx, `UPDATE tables SET current_amount = ? WHERE id = ? AND active_order_id = ?`,
				fresh.GrandTotalPaise, *fresh.TableID, fresh.ID); err != nil {
				return err
			}
		}
		out = fresh
		return nil
	})
	return out, err
}

// AddOrderItemTx inserts a line inside a MutateOpenOrder callback.
func AddOrderItemTx(ctx context.Context, tx *sql.Tx, orderID string, it *models.OrderItem) error {
	return insertOrderItemTx(ctx, tx, orderID, it)
}

func updateOrderMoney(ctx context.Context, q Querier, o *models.Order) error {
	_, err := q.ExecContext(ctx, `UPDATE orders SET subtotal_paise = ?, discount_percent = ?, discount_paise = ?,
		discount_reason = ?, tax_percent = ?, tax_paise = ?, service_paise = ?, service_percent = ?, packaging_paise = ?,
		delivery_paise = ?, grand_total_paise = ?, updated_at = ? WHERE id = ?`,
		o.SubtotalPaise, o.DiscountPercent, o.DiscountPaise, o.DiscountReason, o.TaxPercent, o.TaxPaise,
		o.ServicePaise, o.ServicePercent, o.PackagingPaise, o.DeliveryPaise, o.GrandTotalPaise, TimeStr(Now()), o.ID)
	return err
}

// PatchOrderTx applies a partial order update inside a MutateOpenOrder callback.
func PatchOrderTx(ctx context.Context, tx *sql.Tx, id string, p models.OrderPatch) error {
	sets := []string{}
	args := []any{}
	add := func(col string, v any) {
		sets = append(sets, col+" = ?")
		args = append(args, v)
	}
	if p.Status != nil {
		add("status", *p.Status)
	}
	switch {
	case p.WaiterID != nil && *p.WaiterID == "":
		// "" unassigns the waiter.
		add("waiter_id", nil)
		add("waiter_name", nil)
	case p.WaiterID != nil:
		add("waiter_id", *p.WaiterID)
		if p.WaiterName != nil {
			add("waiter_name", *p.WaiterName)
		}
	case p.WaiterName != nil:
		add("waiter_name", *p.WaiterName)
	}
	if p.OrderNote != nil {
		add("order_note", *p.OrderNote)
	}
	if p.GuestCount != nil {
		add("guest_count", *p.GuestCount)
	}
	if p.CustomerName != nil {
		add("customer_name", *p.CustomerName)
	}
	if p.CustomerPhone != nil {
		add("customer_phone", *p.CustomerPhone)
	}
	if p.DiscountPercent != nil {
		add("discount_percent", *p.DiscountPercent)
		add("discount_paise", 0)
	}
	if p.DiscountPaise != nil {
		add("discount_paise", *p.DiscountPaise)
		add("discount_percent", 0)
	}
	if p.DiscountReason != nil {
		add("discount_reason", *p.DiscountReason)
	}
	switch {
	case p.ServicePaise != nil:
		// A flat amount overrides the percent default.
		add("service_paise", *p.ServicePaise)
		add("service_percent", 0)
	case p.ServicePercent != nil:
		add("service_percent", *p.ServicePercent)
		if *p.ServicePercent == 0 {
			// 0% removes the service charge rather than freezing the old amount.
			add("service_paise", 0)
		}
	}
	if p.TaxPercent != nil {
		add("tax_percent", *p.TaxPercent)
	}
	if p.PackagingPaise != nil {
		add("packaging_paise", *p.PackagingPaise)
	}
	if p.DeliveryPaise != nil {
		add("delivery_paise", *p.DeliveryPaise)
	}
	if len(sets) == 0 {
		return nil
	}
	add("updated_at", TimeStr(Now()))
	args = append(args, id)
	_, err := tx.ExecContext(ctx, `UPDATE orders SET `+strings.Join(sets, ", ")+` WHERE id = ?`, args...)
	return err
}

// CancelOrderItemTx voids a line (idempotent on an already-cancelled line).
func CancelOrderItemTx(ctx context.Context, tx *sql.Tx, orderID, itemID, reason string) error {
	res, err := tx.ExecContext(ctx,
		`UPDATE order_items SET is_cancelled = 1, cancel_reason = ? WHERE id = ? AND order_id = ?`, reason, itemID, orderID)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return httpx.ErrNotFound
	}
	return nil
}

// UpdateOrderItemQuantityTx sets a line quantity inside MutateOpenOrder.
// 0 cancels the line ("Removed from cart"). A cancelled line is never
// revived (409). Raising a line the kitchen already received adds a NEW
// unsent line for the delta (same item/variant/modifiers/snapshot) so the
// next KOT fires exactly the extra portions; newItemID returns its id.
func UpdateOrderItemQuantityTx(ctx context.Context, tx *sql.Tx, o *models.Order, itemID string, quantity int) (newItemID string, err error) {
	if quantity < 0 || quantity > 999 {
		return "", httpx.NewError(400, "invalid_quantity", "Quantity must be between 0 and 999")
	}
	var target *models.OrderItem
	for i := range o.Items {
		if o.Items[i].ID == itemID {
			target = &o.Items[i]
		}
	}
	if target == nil {
		return "", httpx.ErrNotFound
	}
	if target.IsCancelled {
		return "", httpx.NewError(409, "item_cancelled", "A cancelled line cannot be changed; add the item again")
	}
	if quantity == 0 {
		return "", CancelOrderItemTx(ctx, tx, o.ID, itemID, "Removed from cart")
	}
	if target.IsKOTSent && quantity > target.Quantity {
		extra := *target
		extra.ID = ""
		extra.ClientID = nil
		extra.Quantity = quantity - target.Quantity
		extra.TotalPaise = extra.UnitPaise * int64(extra.Quantity)
		extra.IsKOTSent = false
		extra.CancelReason = nil
		if err := insertOrderItemTx(ctx, tx, o.ID, &extra); err != nil {
			return "", err
		}
		return extra.ID, nil
	}
	_, err = tx.ExecContext(ctx,
		`UPDATE order_items SET quantity = ?, total_paise = unit_paise * ? WHERE id = ? AND order_id = ?`,
		quantity, quantity, itemID, o.ID)
	return "", err
}

func (s *Store) SetOrderStatus(ctx context.Context, id, status string) error {
	_, err := s.DB.ExecContext(ctx, `UPDATE orders SET status = ?, updated_at = ? WHERE id = ?`, status, TimeStr(Now()), id)
	return err
}

// ---- Tables: move / merge (transactional) ----

func lockTable(ctx context.Context, tx *sql.Tx, id string) (*models.Table, error) {
	t, err := scanTable(tx.QueryRowContext(ctx, `SELECT `+tableCols+` FROM tables WHERE id = ? AND is_deleted = 0 FOR UPDATE`, id))
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	return t, err
}

// MoveTable re-homes the active order of fromID onto the free table toID.
func (s *Store) MoveTable(ctx context.Context, outletID, fromID, toID string) (*models.Table, *models.Table, error) {
	if fromID == toID {
		return nil, nil, httpx.NewError(400, "invalid_move", "Source and destination are the same table")
	}
	var from, to *models.Table
	err := s.withTx(ctx, func(tx *sql.Tx) error {
		var err error
		if from, err = lockTable(ctx, tx, fromID); err != nil {
			return err
		}
		if to, err = lockTable(ctx, tx, toID); err != nil {
			return err
		}
		if from.OutletID != outletID || to.OutletID != outletID {
			return httpx.ErrNotFound
		}
		if from.ActiveOrderID == nil || *from.ActiveOrderID == "" {
			return httpx.NewError(409, "no_active_order", "Source table has no active order")
		}
		if to.ActiveOrderID != nil && *to.ActiveOrderID != "" {
			return httpx.ErrTableOccupied
		}
		orderID := *from.ActiveOrderID
		var total int64
		var guests int
		if err := tx.QueryRowContext(ctx, `SELECT grand_total_paise, guest_count FROM orders WHERE id = ? FOR UPDATE`, orderID).
			Scan(&total, &guests); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE orders SET table_id = ?, table_number = ?, updated_at = ? WHERE id = ?`,
			to.ID, to.TableNumber, TimeStr(Now()), orderID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE tables SET status = 'occupied', active_order_id = ?, current_amount = ?,
			guest_count = ?, running_minutes = ?, assigned_waiter_id = ? WHERE id = ?`,
			orderID, total, guests, from.RunningMinutes, from.AssignedWaiterID, to.ID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE tables SET status = 'available', active_order_id = NULL, current_amount = 0,
			guest_count = 0, running_minutes = 0, assigned_waiter_id = NULL WHERE id = ?`, from.ID); err != nil {
			return err
		}
		return nil
	})
	if err != nil {
		return nil, nil, err
	}
	f, _ := s.GetTable(ctx, fromID)
	t, err := s.GetTable(ctx, toID)
	return f, t, err
}

// MergeTables folds secondaryID into primaryID (mirrors the POS: the
// secondary's active order is re-homed onto the primary; the primary adopts
// it when it has none). The primary's running amount is recomputed from every
// open order now seated on it.
func (s *Store) MergeTables(ctx context.Context, outletID, primaryID, secondaryID string) (*models.Table, error) {
	if primaryID == secondaryID {
		return nil, httpx.NewError(400, "invalid_merge", "Cannot merge a table with itself")
	}
	err := s.withTx(ctx, func(tx *sql.Tx) error {
		primary, err := lockTable(ctx, tx, primaryID)
		if err != nil {
			return err
		}
		secondary, err := lockTable(ctx, tx, secondaryID)
		if err != nil {
			return err
		}
		if primary.OutletID != outletID || secondary.OutletID != outletID {
			return httpx.ErrNotFound
		}
		if secondary.ActiveOrderID != nil && *secondary.ActiveOrderID != "" {
			orphan := *secondary.ActiveOrderID
			if _, err := tx.ExecContext(ctx, `UPDATE orders SET table_id = ?, table_number = ?, updated_at = ? WHERE id = ?`,
				primary.ID, primary.TableNumber, TimeStr(Now()), orphan); err != nil {
				return err
			}
			if primary.ActiveOrderID == nil || *primary.ActiveOrderID == "" {
				if _, err := tx.ExecContext(ctx, `UPDATE tables SET active_order_id = ?, status = 'occupied' WHERE id = ?`,
					orphan, primary.ID); err != nil {
					return err
				}
			}
		}
		if _, err := tx.ExecContext(ctx, `UPDATE tables SET merged_with_table_id = ?, active_order_id = NULL,
			current_amount = 0, guest_count = 0, status = 'occupied' WHERE id = ?`, primary.ID, secondary.ID); err != nil {
			return err
		}
		_, err = tx.ExecContext(ctx, `UPDATE tables SET current_amount = (
			SELECT COALESCE(SUM(grand_total_paise), 0) FROM orders
			WHERE table_id = ? AND status NOT IN ('completed','cancelled','refunded')) WHERE id = ?`, primary.ID, primary.ID)
		return err
	})
	if err != nil {
		return nil, err
	}
	return s.GetTable(ctx, primaryID)
}

// UnmergeTable detaches a merged table; with no order of its own it becomes
// available again.
func (s *Store) UnmergeTable(ctx context.Context, id string) (*models.Table, error) {
	err := s.withTx(ctx, func(tx *sql.Tx) error {
		t, err := lockTable(ctx, tx, id)
		if err != nil {
			return err
		}
		status := t.Status
		if t.ActiveOrderID == nil || *t.ActiveOrderID == "" {
			status = "available"
		}
		_, err = tx.ExecContext(ctx, `UPDATE tables SET merged_with_table_id = NULL, status = ? WHERE id = ?`, status, id)
		return err
	})
	if err != nil {
		return nil, err
	}
	return s.GetTable(ctx, id)
}

// ---- Payments ----

// PayInput is a validated payment; Legs are the amounts booked per tender
// (sum == grand total; empty for credit).
type PayInput struct {
	OrderID       string
	ExpectedTotal int64
	Method        string
	Legs          []models.PaymentSplit
	Received      int64
	Change        int64
	Reference     *string
	CustomerID    *string
	StaffID       string
	StaffName     string
}

// PayOrder settles an order in ONE transaction: row-lock + status guard (a
// concurrent second pay gets 409 already_paid), invoice number, tender legs,
// shift sales per leg (or customer credit for method "credit"), customer
// rollup and table release. Nothing is booked unless everything commits.
func (s *Store) PayOrder(ctx context.Context, in PayInput) error {
	return s.withTx(ctx, func(tx *sql.Tx) error {
		var status, outletID, number string
		var total int64
		var tableID, phone, cname sql.NullString
		err := tx.QueryRowContext(ctx, `SELECT status, outlet_id, order_number, grand_total_paise, table_id,
			customer_phone, customer_name FROM orders WHERE id = ? FOR UPDATE`, in.OrderID).
			Scan(&status, &outletID, &number, &total, &tableID, &phone, &cname)
		if err == sql.ErrNoRows {
			return httpx.ErrNotFound
		}
		if err != nil {
			return err
		}
		if IsClosedStatus(status) {
			return ErrAlreadyPaid
		}
		if total != in.ExpectedTotal {
			return ErrOrderChanged
		}
		var shiftID string
		err = tx.QueryRowContext(ctx, `SELECT id FROM shifts WHERE outlet_id = ? AND status = 'open'`, outletID).Scan(&shiftID)
		if err == sql.ErrNoRows {
			return ErrShiftRequired
		}
		if err != nil {
			return err
		}
		num, err := s.NextCounter(ctx, tx, outletID, "invoice")
		if err != nil {
			return err
		}
		invoice := fmt.Sprintf("INV-%d", 1044+num)
		now := TimeStr(Now())
		res, err := tx.ExecContext(ctx, `UPDATE orders SET status = 'completed', paid_at = ?, invoice_number = ?,
			payment_method = ?, payment_reference = ?, customer_id = COALESCE(?, customer_id), paid_paise = ?, change_paise = ?,
			updated_at = ? WHERE id = ? AND status NOT IN ('completed','cancelled','refunded')`,
			now, invoice, in.Method, in.Reference, in.CustomerID, in.Received, in.Change, now, in.OrderID)
		if err != nil {
			return err
		}
		if n, _ := res.RowsAffected(); n == 0 {
			return ErrAlreadyPaid
		}
		for _, leg := range in.Legs {
			if leg.Paise <= 0 {
				continue
			}
			if _, err := tx.ExecContext(ctx, `INSERT INTO order_payments (id, order_id, method, amount_paise) VALUES (?, ?, ?, ?)`,
				NewID("op"), in.OrderID, leg.Method, leg.Paise); err != nil {
				return err
			}
			if err := addShiftSales(ctx, tx, shiftID, leg.Method, leg.Paise); err != nil {
				return err
			}
		}
		if in.Method == "credit" {
			if in.CustomerID == nil {
				return httpx.NewError(400, "invalid_customer", "customer_id is required for credit payments")
			}
			if _, err := tx.ExecContext(ctx, `INSERT INTO order_payments (id, order_id, method, amount_paise) VALUES (?, ?, 'credit', ?)`,
				NewID("op"), in.OrderID, total); err != nil {
				return err
			}
			if total > 0 {
				if err := bookCreditTx(ctx, tx, outletID, *in.CustomerID, "sale", total,
					"Credit sale "+number, in.StaffID, in.StaffName); err != nil {
					if errors.Is(err, httpx.ErrNotFound) {
						return httpx.NewError(400, "invalid_customer", "Customer not found in this outlet")
					}
					return err
				}
			}
		}
		// Customer rollup: the attached customer wins, else the phone on the order.
		if in.CustomerID != nil {
			res, err := tx.ExecContext(ctx, `UPDATE customers SET visits = visits + 1, lifetime_spend = lifetime_spend + ?,
				last_visit = ? WHERE id = ? AND outlet_id = ?`, total, now, *in.CustomerID, outletID)
			if err != nil {
				return err
			}
			if n, _ := res.RowsAffected(); n == 0 {
				return httpx.NewError(400, "invalid_customer", "Customer not found in this outlet")
			}
		} else if phone.Valid && NormalizePhone(phone.String) != "" {
			name := "Guest"
			if cname.Valid && cname.String != "" {
				name = cname.String
			}
			if _, err := tx.ExecContext(ctx, `INSERT INTO customers (id, outlet_id, name, phone_norm, visits, lifetime_spend, last_visit)
				VALUES (?, ?, ?, ?, 1, ?, ?)
				ON CONFLICT (outlet_id, phone_norm) DO UPDATE SET visits = customers.visits + 1,
				  lifetime_spend = customers.lifetime_spend + EXCLUDED.lifetime_spend, last_visit = EXCLUDED.last_visit,
				  is_deleted = 0`,
				NewID("c"), outletID, name, NormalizePhone(phone.String), total, now); err != nil {
				return err
			}
		}
		if tableID.Valid && tableID.String != "" {
			if _, err := tx.ExecContext(ctx, `UPDATE tables SET status = 'available', active_order_id = NULL,
				current_amount = 0, running_minutes = 0, guest_count = 0, assigned_waiter_id = NULL
				WHERE id = ? AND (active_order_id = ? OR active_order_id IS NULL OR active_order_id = '')`,
				tableID.String, in.OrderID); err != nil {
				return err
			}
		}
		return nil
	})
}

// ---- Refunds ----

type RefundInput struct {
	OrderID    string
	Amount     int64 // 0 with IsFull = everything still refundable
	IsFull     bool
	Mode       string
	Reason     string
	IsCash     bool // leaves the physical drawer (tender-aware, D-004)
	CreditNote bool // credit sale refunded to the customer's outstanding
	StaffID    string
	StaffName  string
}

// RefundOrder records a refund in one transaction. The cap is the grand
// total minus what was already refunded — never paid_paise, which includes
// cash change handed back. Reaching the total flips the order to 'refunded'.
func (s *Store) RefundOrder(ctx context.Context, in RefundInput) (*models.Refund, error) {
	var out *models.Refund
	err := s.withTx(ctx, func(tx *sql.Tx) error {
		var status, outletID, number string
		var total, refunded int64
		var customerID sql.NullString
		err := tx.QueryRowContext(ctx, `SELECT status, outlet_id, order_number, grand_total_paise, refunded_paise, customer_id
			FROM orders WHERE id = ? FOR UPDATE`, in.OrderID).
			Scan(&status, &outletID, &number, &total, &refunded, &customerID)
		if err == sql.ErrNoRows {
			return httpx.ErrNotFound
		}
		if err != nil {
			return err
		}
		if status == "refunded" {
			return httpx.NewError(409, "already_refunded", "Order is already fully refunded")
		}
		if status != "completed" {
			return httpx.NewError(409, "invalid_state", "Only paid orders can be refunded")
		}
		remaining := total - refunded
		amount := in.Amount
		if in.IsFull && amount == 0 {
			amount = remaining
		}
		if amount <= 0 {
			return httpx.ErrInvalidAmount
		}
		if amount > remaining {
			return httpx.NewError(400, "refund_exceeds_total", "Refund exceeds the bill total still refundable")
		}
		var shiftID sql.NullString
		err = tx.QueryRowContext(ctx, `SELECT id FROM shifts WHERE outlet_id = ? AND status = 'open'`, outletID).Scan(&shiftID)
		if err != nil && err != sql.ErrNoRows {
			return err
		}
		switch {
		case in.CreditNote:
			if !customerID.Valid {
				return httpx.NewError(409, "invalid_state", "Credit order has no customer to credit")
			}
			if _, err := tx.ExecContext(ctx, `UPDATE customers SET outstanding_paise = GREATEST(0, outstanding_paise - ?)
				WHERE id = ? AND outlet_id = ?`, amount, customerID.String, outletID); err != nil {
				return err
			}
			if _, err := tx.ExecContext(ctx, `INSERT INTO customer_credit_log (id, outlet_id, customer_id, kind, amount_paise, reason, staff_id, staff_name, ts)
				VALUES (?, ?, ?, 'settlement', ?, ?, ?, ?, ?)`, NewID("ccl"), outletID, customerID.String, amount,
				"Refund on "+number, in.StaffID, in.StaffName, TimeStr(Now())); err != nil {
				return err
			}
		case in.IsCash && !shiftID.Valid:
			return httpx.NewError(409, "shift_required", "Open a shift before a cash refund")
		case shiftID.Valid:
			if err := addShiftRefund(ctx, tx, shiftID.String, in.IsCash, amount); err != nil {
				return err
			}
		}
		ts := Now()
		r := &models.Refund{ID: NewID("rf"), OutletID: outletID, OrderID: in.OrderID, Amount: amount, Mode: in.Mode,
			Reason: in.Reason, StaffID: &in.StaffID, StaffName: &in.StaffName, Ts: ts}
		if shiftID.Valid && !in.CreditNote {
			r.ShiftID = &shiftID.String
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO refunds (id, outlet_id, order_id, amount_paise, mode, reason, staff_id, staff_name, ts, shift_id)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`, r.ID, outletID, in.OrderID, amount, in.Mode, in.Reason,
			in.StaffID, in.StaffName, TimeStr(ts), r.ShiftID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE orders SET refunded_paise = refunded_paise + ?,
			status = CASE WHEN refunded_paise + ? >= grand_total_paise THEN 'refunded' ELSE status END,
			updated_at = ? WHERE id = ?`, amount, amount, TimeStr(ts), in.OrderID); err != nil {
			return err
		}
		out = r
		return nil
	})
	return out, err
}

// NormalizePhone keeps digits only (customer dedupe key).
func NormalizePhone(p string) string {
	var b strings.Builder
	for _, r := range p {
		if r >= '0' && r <= '9' {
			b.WriteRune(r)
		}
	}
	return b.String()
}

// ---- Idempotency ----

// IdemPending is the response_code of a reserved-but-unfinished key.
const IdemPending = 0

// idemStaleAfter: a pending reservation older than this is considered
// abandoned (crashed request) and may be taken over by a retry.
const idemStaleAfter = 2 * time.Minute

var ErrIdemInProgress = httpx.NewError(409, "in_progress", "This request is already being processed; retry shortly")

// ReserveIdempotencyKey claims key before the write runs. It returns
// (code, body, true) when a finished response exists (replay it), and
// ErrIdemInProgress when a concurrent duplicate holds the reservation.
func (s *Store) ReserveIdempotencyKey(ctx context.Context, key string) (int, []byte, bool, error) {
	now := Now()
	res, err := s.DB.ExecContext(ctx, `INSERT INTO idempotency_keys (key, response_code, response_body, created_at)
		VALUES (?, 0, '', ?) ON CONFLICT (key) DO NOTHING`, key, TimeStr(now))
	if err != nil {
		return 0, nil, false, err
	}
	if n, _ := res.RowsAffected(); n == 1 {
		return 0, nil, false, nil
	}
	var code int
	var body []byte
	var created string
	err = s.DB.QueryRowContext(ctx, `SELECT response_code, response_body, created_at FROM idempotency_keys WHERE key = ?`, key).
		Scan(&code, &body, &created)
	if errors.Is(err, sql.ErrNoRows) {
		// Released between our insert and read: try once more.
		return s.ReserveIdempotencyKey(ctx, key)
	}
	if err != nil {
		return 0, nil, false, err
	}
	if code != IdemPending {
		return code, body, true, nil
	}
	if now.Sub(ParseTime(created)) > idemStaleAfter {
		res, err := s.DB.ExecContext(ctx, `UPDATE idempotency_keys SET created_at = ? WHERE key = ? AND response_code = 0 AND created_at = ?`,
			TimeStr(now), key, created)
		if err != nil {
			return 0, nil, false, err
		}
		if n, _ := res.RowsAffected(); n == 1 {
			return 0, nil, false, nil
		}
	}
	return 0, nil, false, ErrIdemInProgress
}

// CompleteIdempotencyKey stores the finished response for replay.
func (s *Store) CompleteIdempotencyKey(ctx context.Context, key string, code int, body []byte) error {
	_, err := s.DB.ExecContext(ctx, `UPDATE idempotency_keys SET response_code = ?, response_body = ? WHERE key = ?`,
		code, body, key)
	return err
}

// ReleaseIdempotencyKey drops a reservation whose write failed, so the
// client may retry (errors are never cached).
func (s *Store) ReleaseIdempotencyKey(ctx context.Context, key string) error {
	_, err := s.DB.ExecContext(ctx, `DELETE FROM idempotency_keys WHERE key = ? AND response_code = 0`, key)
	return err
}

// ---- KOTs ----

// FireKOT sends every unsent, uncancelled line of an open order to the
// kitchen in one transaction (lines row-locked, so two terminals firing at
// once cannot both send the same portions). build fills the KOT header
// from the locked order.
func (s *Store) FireKOT(ctx context.Context, orderID string, build func(o *models.Order, num int) *models.KOT) (*models.KOT, error) {
	var kot *models.KOT
	err := s.withTx(ctx, func(tx *sql.Tx) error {
		o, err := s.getOrderQ(ctx, tx, orderID, true)
		if err != nil {
			return err
		}
		if IsClosedStatus(o.Status) {
			return ErrOrderClosed
		}
		rows, err := tx.QueryContext(ctx, `SELECT id FROM order_items WHERE order_id = ? AND is_kot_sent = 0
			AND is_cancelled = 0 ORDER BY seq FOR UPDATE`, orderID)
		if err != nil {
			return err
		}
		locked := map[string]bool{}
		for rows.Next() {
			var id string
			if err := rows.Scan(&id); err != nil {
				rows.Close()
				return err
			}
			locked[id] = true
		}
		rows.Close()
		if len(locked) == 0 {
			return httpx.NewError(409, "nothing_to_fire", "No unsent items on this order")
		}
		num, err := s.NextCounter(ctx, tx, o.OutletID, "kot")
		if err != nil {
			return err
		}
		kot = build(o, num)
		kot.Items = []models.KOTItem{}
		var ids []string
		for _, it := range o.Items {
			if !locked[it.ID] {
				continue
			}
			kot.Items = append(kot.Items, models.KOTItem{OrderItemID: it.ID, Name: it.Name, Quantity: it.Quantity, IsVeg: it.IsVeg})
			ids = append(ids, it.ID)
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO kots (id, outlet_id, kot_number, order_id, status, waiter_id,
			waiter_name, table_number, order_type, note, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			kot.ID, kot.OutletID, kot.KOTNumber, kot.OrderID, kot.Status, kot.WaiterID, kot.WaiterName, kot.TableNumber,
			kot.OrderType, kot.Note, TimeStr(kot.CreatedAt)); err != nil {
			return err
		}
		for _, it := range kot.Items {
			if _, err := tx.ExecContext(ctx, `INSERT INTO kot_items (kot_id, order_item_id, name, quantity, is_veg) VALUES (?, ?, ?, ?, ?)`,
				kot.ID, it.OrderItemID, it.Name, it.Quantity, b2i(it.IsVeg)); err != nil {
				return err
			}
		}
		if _, err := tx.ExecContext(ctx, `UPDATE order_items SET is_kot_sent = 1 WHERE id = ANY(?)`, pq.Array(ids)); err != nil {
			return err
		}
		if o.Status == "received" {
			if _, err := tx.ExecContext(ctx, `UPDATE orders SET status = 'preparing', updated_at = ? WHERE id = ?`,
				TimeStr(Now()), o.ID); err != nil {
				return err
			}
		}
		if o.TableID != nil {
			if _, err := tx.ExecContext(ctx, `UPDATE tables SET status = 'occupied', active_order_id = ?
				WHERE id = ? AND (active_order_id IS NULL OR active_order_id = '' OR active_order_id = ?)`,
				o.ID, *o.TableID, o.ID); err != nil {
				return err
			}
		}
		return nil
	})
	return kot, err
}

func (s *Store) ListKOTs(ctx context.Context, outletID, status string) ([]models.KOT, error) {
	q := `SELECT id, outlet_id, kot_number, order_id, status, waiter_id, waiter_name, table_number, order_type, note, created_at
		FROM kots WHERE outlet_id = ?`
	args := []any{outletID}
	if status != "" {
		q += ` AND status = ?`
		args = append(args, status)
	}
	q += ` ORDER BY created_at DESC LIMIT 200`
	rows, err := s.DB.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []models.KOT{}
	pos := map[string]int{}
	var ids []string
	for rows.Next() {
		k, err := scanKOT(rows)
		if err != nil {
			return nil, err
		}
		pos[k.ID] = len(out)
		ids = append(ids, k.ID)
		out = append(out, *k)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	rows.Close()
	if len(ids) == 0 {
		return out, nil
	}
	irows, err := s.DB.QueryContext(ctx, `SELECT kot_id, order_item_id, name, quantity, COALESCE(is_veg, 1)
		FROM kot_items WHERE kot_id = ANY(?)`, pq.Array(ids))
	if err != nil {
		return nil, err
	}
	defer irows.Close()
	for irows.Next() {
		var kid string
		var it models.KOTItem
		var veg int
		if err := irows.Scan(&kid, &it.OrderItemID, &it.Name, &it.Quantity, &veg); err != nil {
			return nil, err
		}
		it.IsVeg = veg == 1
		if i, ok := pos[kid]; ok {
			out[i].Items = append(out[i].Items, it)
		}
	}
	return out, irows.Err()
}

func scanKOT(sc interface{ Scan(...any) error }) (*models.KOT, error) {
	k := &models.KOT{}
	var waiterID, waiterName, tableNumber, note sql.NullString
	var createdAt string
	if err := sc.Scan(&k.ID, &k.OutletID, &k.KOTNumber, &k.OrderID, &k.Status, &waiterID, &waiterName,
		&tableNumber, &k.OrderType, &note, &createdAt); err != nil {
		return nil, err
	}
	k.WaiterID = nullIfEmpty(waiterID)
	k.WaiterName = nullIfEmpty(waiterName)
	k.TableNumber = nullIfEmpty(tableNumber)
	k.Note = nullIfEmpty(note)
	k.CreatedAt = ParseTime(createdAt)
	k.Items = []models.KOTItem{}
	return k, nil
}

func (s *Store) GetKOT(ctx context.Context, id string) (*models.KOT, error) {
	k, err := scanKOT(s.DB.QueryRowContext(ctx, `SELECT id, outlet_id, kot_number, order_id, status, waiter_id, waiter_name,
		table_number, order_type, note, created_at FROM kots WHERE id = ?`, id))
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	rows, err := s.DB.QueryContext(ctx, `SELECT order_item_id, name, quantity, COALESCE(is_veg, 1) FROM kot_items WHERE kot_id = ?`, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var it models.KOTItem
		var veg int
		if err := rows.Scan(&it.OrderItemID, &it.Name, &it.Quantity, &veg); err != nil {
			return nil, err
		}
		it.IsVeg = veg == 1
		k.Items = append(k.Items, it)
	}
	return k, rows.Err()
}

// Allowed KOT transitions (state machine): new→preparing→ready→served;
// cancellation allowed before served only.
func KOTTransitionAllowed(from, to string) bool {
	switch from {
	case "new":
		return to == "preparing" || to == "ready" || to == "cancelled"
	case "preparing":
		return to == "ready" || to == "cancelled"
	case "ready":
		return to == "served" || to == "cancelled"
	case "served", "cancelled":
		return false
	}
	return false
}

func (s *Store) SetKOTStatus(ctx context.Context, id, status string) error {
	res, err := s.DB.ExecContext(ctx, `UPDATE kots SET status = ? WHERE id = ?`, status, id)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return httpx.ErrNotFound
	}
	return nil
}

// Shift booking helpers ------------------------------------------------------

// addShiftSales books one tender leg onto an OPEN shift (0 rows = the shift
// closed under us → shift_required).
func addShiftSales(ctx context.Context, q Querier, shiftID, method string, amount int64) error {
	col := map[string]string{"cash": "cash_sales", "upi": "upi_sales", "card": "card_sales"}[method]
	if col == "" {
		return fmt.Errorf("unknown method %q", method)
	}
	res, err := q.ExecContext(ctx, `UPDATE shifts SET `+col+` = `+col+` + ? WHERE id = ? AND status = 'open'`, amount, shiftID)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrShiftRequired
	}
	return nil
}

func addShiftRefund(ctx context.Context, q Querier, shiftID string, cash bool, amount int64) error {
	col := "refunds_digital"
	if cash {
		col = "refunds_cash"
	}
	_, err := q.ExecContext(ctx, `UPDATE shifts SET `+col+` = `+col+` + ? WHERE id = ?`, amount, shiftID)
	return err
}

// AddShiftExpense moves an expense into (sign +1) or out of (-1) a shift's
// drawer math.
func (s *Store) AddShiftExpense(ctx context.Context, shiftID string, amount int64, sign int64) error {
	_, err := s.DB.ExecContext(ctx, `UPDATE shifts SET expenses = GREATEST(0, expenses + ?) WHERE id = ?`, sign*amount, shiftID)
	return err
}
