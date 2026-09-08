package store

import (
	"context"
	"database/sql"
	"fmt"
	"strings"

	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/models"
)

// ---- Orders ----

func (s *Store) GetOrder(ctx context.Context, id string) (*models.Order, error) {
	o := &models.Order{}
	var tableID, custName, custPhone, addr, waiterID, waiterName, note, discountReason,
		invoice, method, idemKey, clientID sql.NullString
	var tableNumber sql.NullString
	var paidAt sql.NullString
	var createdAt, updatedAt string
	var inclusive int
	err := s.DB.QueryRowContext(ctx, `SELECT id, client_id, outlet_id, order_number, type, status, table_id, table_number,
		customer_name, customer_phone, delivery_address, waiter_id, waiter_name, guest_count, order_note,
		subtotal_paise, discount_percent, discount_paise, discount_reason, tax_percent, is_tax_inclusive, tax_paise,
		service_paise, packaging_paise, delivery_paise, grand_total_paise, invoice_number, paid_at,
		payment_method, paid_paise, change_paise, idempotency_key, created_at, updated_at
		FROM orders WHERE id = ?`, id).
		Scan(&o.ID, &clientID, &o.OutletID, &o.OrderNumber, &o.Type, &o.Status, &tableID, &tableNumber,
			&custName, &custPhone, &addr, &waiterID, &waiterName, &o.GuestCount, &note,
			&o.SubtotalPaise, &o.DiscountPercent, &o.DiscountPaise, &discountReason, &o.TaxPercent, &inclusive, &o.TaxPaise,
			&o.ServicePaise, &o.PackagingPaise, &o.DeliveryPaise, &o.GrandTotalPaise, &invoice, &paidAt,
			&method, &o.PaidPaise, &o.ChangePaise, &idemKey, &createdAt, &updatedAt)
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	copyNull := func(n sql.NullString) *string {
		if n.Valid {
			return &n.String
		}
		return nil
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
	o.IdempotencyKey = copyNull(idemKey)
	if paidAt.Valid {
		t := ParseTime(paidAt.String)
		o.PaidAt = &t
	}
	o.CreatedAt = ParseTime(createdAt)
	o.UpdatedAt = ParseTime(updatedAt)

	items, err := s.ListOrderItems(ctx, id)
	if err != nil {
		return nil, err
	}
	o.Items = items
	return o, nil
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

func (s *Store) ListOrderItems(ctx context.Context, orderID string) ([]models.OrderItem, error) {	rows, err := s.DB.QueryContext(ctx, `SELECT oi.id, oi.client_id, oi.menu_item_id, oi.variant_id, oi.quantity, oi.unit_paise,
		oi.total_paise, oi.note, oi.is_kot_sent, oi.is_cancelled, oi.cancel_reason, COALESCE(mi.name,'')
		FROM order_items oi LEFT JOIN menu_items mi ON mi.id = oi.menu_item_id
		WHERE oi.order_id = ? ORDER BY oi.seq`, orderID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []models.OrderItem{}
	for rows.Next() {
		var it models.OrderItem
		var variant, note, reason, clientID sql.NullString
		var kot, cancelled int
		if err := rows.Scan(&it.ID, &clientID, &it.MenuItemID, &variant, &it.Quantity, &it.UnitPaise, &it.TotalPaise,
			&note, &kot, &cancelled, &reason, &it.Name); err != nil {
			return nil, err
		}
		if clientID.Valid {
			it.ClientID = &clientID.String
		}
		if variant.Valid {
			it.VariantID = &variant.String
		}
		it.Note = nullIfEmpty(note)
		it.IsKOTSent = kot == 1
		it.IsCancelled = cancelled == 1
		it.CancelReason = nullIfEmpty(reason)
		it.Modifiers = []models.OrderModifier{}
		out = append(out, it)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	// Modifiers per item
	mrows, err := s.DB.QueryContext(ctx, `SELECT order_item_id, modifier_item_id, name, price_paise FROM order_item_modifiers ORDER BY seq`)
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
		for i := range out {
			if out[i].ID == itemID {
				out[i].Modifiers = append(out[i].Modifiers, m)
			}
		}
	}
	return out, nil
}

func nullIfEmpty(n sql.NullString) *string {
	if n.Valid && n.String != "" {
		return &n.String
	}
	return nil
}

func (s *Store) ListOrders(ctx context.Context, outletID, status string, limit int) ([]models.Order, error) {
	q := `SELECT id FROM orders WHERE outlet_id = ?`
	args := []any{outletID}
	if status == "running" {
		q += ` AND status NOT IN ('completed','cancelled')`
	} else if status != "" {
		q += ` AND status = ?`
		args = append(args, status)
	}
	q += ` ORDER BY created_at DESC LIMIT ?`
	args = append(args, limit)
	rows, err := s.DB.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	out := []models.Order{}
	for _, id := range ids {
		o, err := s.GetOrder(ctx, id)
		if err != nil {
			return nil, err
		}
		out = append(out, *o)
	}
	return out, nil
}

// InsertOrder writes the order + items inside one transaction.
func (s *Store) InsertOrder(ctx context.Context, o *models.Order) error {
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	_, err = tx.ExecContext(ctx, `INSERT INTO orders (id, client_id, outlet_id, order_number, type, status, table_id, table_number,
		customer_name, customer_phone, delivery_address, waiter_id, waiter_name, guest_count, order_note,
		subtotal_paise, discount_percent, discount_paise, discount_reason, tax_percent, is_tax_inclusive, tax_paise,
		service_paise, packaging_paise, delivery_paise, grand_total_paise, idempotency_key, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		o.ID, o.ClientID, o.OutletID, o.OrderNumber, o.Type, o.Status, o.TableID, o.TableNumber,
		o.CustomerName, o.CustomerPhone, o.DeliveryAddress, o.WaiterID, o.WaiterName, o.GuestCount, o.OrderNote,
		o.SubtotalPaise, o.DiscountPercent, o.DiscountPaise, o.DiscountReason, o.TaxPercent, b2i(o.IsTaxInclusive), o.TaxPaise,
		o.ServicePaise, o.PackagingPaise, o.DeliveryPaise, o.GrandTotalPaise, o.IdempotencyKey,
		TimeStr(o.CreatedAt), TimeStr(o.UpdatedAt))
	if err != nil {
		return err
	}
	for i := range o.Items {
		if err := insertOrderItemTx(ctx, tx, o.ID, &o.Items[i]); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func insertOrderItemTx(ctx context.Context, tx *sql.Tx, orderID string, it *models.OrderItem) error {
	id := NewID("oi")
	it.ID = id
	_, err := tx.ExecContext(ctx, `INSERT INTO order_items (id, client_id, order_id, menu_item_id, variant_id, quantity,
		unit_paise, total_paise, note, is_kot_sent, is_cancelled, cancel_reason) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		id, it.ClientID, orderID, it.MenuItemID, it.VariantID, it.Quantity, it.UnitPaise, it.TotalPaise,
		it.Note, b2i(it.IsKOTSent), b2i(it.IsCancelled), it.CancelReason)
	if err != nil {
		return err
	}
	for _, m := range it.Modifiers {
		if _, err := tx.ExecContext(ctx,
			`INSERT INTO order_item_modifiers (order_item_id, modifier_item_id, name, price_paise) VALUES (?, ?, ?, ?)`,
			id, m.ModifierItemID, m.Name, m.PricePaise); err != nil {
			return err
		}
	}
	return nil
}

// AddOrderItem appends an item and re-applies billing math in one txn.
func (s *Store) AddOrderItem(ctx context.Context, orderID string, it *models.OrderItem, recompute func(o *models.Order)) error {
	if it.ID == "" {
		it.ID = NewID("oi")
	}
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()
	if _, err := tx.ExecContext(ctx, `INSERT INTO order_items (id, client_id, order_id, menu_item_id, variant_id, quantity,
		unit_paise, total_paise, note, is_kot_sent, is_cancelled, cancel_reason) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, NULL)`,
		it.ID, it.ClientID, orderID, it.MenuItemID, it.VariantID, it.Quantity, it.UnitPaise, it.TotalPaise, it.Note); err != nil {
		return err
	}
	for _, m := range it.Modifiers {
		if _, err := tx.ExecContext(ctx,
			`INSERT INTO order_item_modifiers (order_item_id, modifier_item_id, name, price_paise) VALUES (?, ?, ?, ?)`,
			it.ID, m.ModifierItemID, m.Name, m.PricePaise); err != nil {
			return err
		}
	}
	if err := tx.Commit(); err != nil {
		return err
	}
	o, err := s.GetOrder(ctx, orderID)
	if err != nil {
		return err
	}
	recompute(o)
	return s.UpdateOrderMoney(ctx, o)
}

func (s *Store) UpdateOrderMoney(ctx context.Context, o *models.Order) error {
	_, err := s.DB.ExecContext(ctx, `UPDATE orders SET subtotal_paise = ?, discount_percent = ?, discount_paise = ?,
		discount_reason = ?, tax_percent = ?, tax_paise = ?, service_paise = ?, packaging_paise = ?, delivery_paise = ?,
		grand_total_paise = ?, updated_at = ? WHERE id = ?`,
		o.SubtotalPaise, o.DiscountPercent, o.DiscountPaise, o.DiscountReason, o.TaxPercent, o.TaxPaise,
		o.ServicePaise, o.PackagingPaise, o.DeliveryPaise, o.GrandTotalPaise, TimeStr(Now()), o.ID)
	return err
}

func (s *Store) PatchOrder(ctx context.Context, id string, p models.OrderPatch) error {
	sets := []string{}
	args := []any{}
	add := func(col string, v any) {
		sets = append(sets, col+" = ?")
		args = append(args, v)
	}
	if p.Status != nil {
		add("status", *p.Status)
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
	if p.ServicePaise != nil {
		add("service_paise", *p.ServicePaise)
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
	_, err := s.DB.ExecContext(ctx, `UPDATE orders SET `+strings.Join(sets, ", ")+` WHERE id = ?`, args...)
	return err
}

func (s *Store) SetOrderStatus(ctx context.Context, id, status string) error {
	_, err := s.DB.ExecContext(ctx, `UPDATE orders SET status = ?, updated_at = ? WHERE id = ?`, status, TimeStr(Now()), id)
	return err
}

// PatchOrderTable re-homes an order onto another table (move/merge flows).
func (s *Store) PatchOrderTable(ctx context.Context, orderID, tableID, tableNumber string) error {
	_, err := s.DB.ExecContext(ctx, `UPDATE orders SET table_id = ?, table_number = ?, updated_at = ? WHERE id = ?`,
		tableID, tableNumber, TimeStr(Now()), orderID)
	return err
}

func (s *Store) CancelOrderItem(ctx context.Context, orderID, itemID, reason string) error {
	res, err := s.DB.ExecContext(ctx,
		`UPDATE order_items SET is_cancelled = 1, cancel_reason = ? WHERE id = ? AND order_id = ?`, reason, itemID, orderID)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return httpx.ErrNotFound
	}
	return nil
}

// UpdateOrderItemQuantity sets a line quantity. A quantity of 0 cancels the
// line with an audit reason (mirrors removing it from the cart).
func (s *Store) UpdateOrderItemQuantity(ctx context.Context, orderID, itemID string, quantity int) error {
	if quantity < 0 {
		return httpx.NewError(400, "invalid_quantity", "Quantity cannot be negative")
	}
	if quantity == 0 {
		return s.CancelOrderItem(ctx, orderID, itemID, "Removed from cart")
	}
	res, err := s.DB.ExecContext(ctx,
		`UPDATE order_items SET quantity = ?, total_paise = unit_paise * ?, is_cancelled = 0, cancel_reason = NULL
		 WHERE id = ? AND order_id = ?`, quantity, quantity, itemID, orderID)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return httpx.ErrNotFound
	}
	return nil
}

func (s *Store) MarkItemsKOTSent(ctx context.Context, itemIDs []string) error {
	if len(itemIDs) == 0 {
		return nil
	}
	ph := strings.TrimRight(strings.Repeat("?,", len(itemIDs)), ",")
	args := make([]any, len(itemIDs))
	for i, id := range itemIDs {
		args[i] = id
	}
	_, err := s.DB.ExecContext(ctx, `UPDATE order_items SET is_kot_sent = 1 WHERE id IN (`+ph+`)`, args...)
	return err
}

// ---- Payments ----

func (s *Store) CompleteOrderPayment(ctx context.Context, o *models.Order, method, invoice string, received, change int64) error {
	now := Now()
	_, err := s.DB.ExecContext(ctx, `UPDATE orders SET status = 'completed', paid_at = ?, invoice_number = ?,
		payment_method = ?, paid_paise = ?, change_paise = ?, updated_at = ? WHERE id = ?`,
		TimeStr(now), invoice, method, received, change, TimeStr(now), o.ID)
	if err != nil {
		return err
	}
	// Free the table if dine-in.
	if o.TableID != nil {
		_, err = s.DB.ExecContext(ctx, `UPDATE tables SET status = 'available', active_order_id = NULL,
			current_amount = 0, running_minutes = 0, guest_count = 0, assigned_waiter_id = NULL WHERE id = ?`, *o.TableID)
		if err != nil {
			return err
		}
	}
	return nil
}

func (s *Store) UpdateTableForOrder(ctx context.Context, tableID, orderID string, amount int64, guests int) error {
	_, err := s.DB.ExecContext(ctx, `UPDATE tables SET status = 'occupied', active_order_id = ?,
		current_amount = ?, guest_count = ? WHERE id = ?`, orderID, amount, guests, tableID)
	return err
}

func (s *Store) TableHasActiveOrder(ctx context.Context, tableID string) (bool, string, error) {
	var active sql.NullString
	err := s.DB.QueryRowContext(ctx, `SELECT active_order_id FROM tables WHERE id = ?`, tableID).Scan(&active)
	if err == sql.ErrNoRows {
		return false, "", httpx.ErrNotFound
	}
	if err != nil {
		return false, "", err
	}
	if active.Valid && active.String != "" {
		return true, active.String, nil
	}
	return false, "", nil
}

// RecordCustomerSpend upserts the customer and adds a visit + spend.
func (s *Store) RecordCustomerSpend(ctx context.Context, outletID string, name, phone string, spend int64) error {
	norm := NormalizePhone(phone)
	var id string
	err := s.DB.QueryRowContext(ctx, `SELECT id FROM customers WHERE outlet_id = ? AND phone_norm = ?`, outletID, norm).Scan(&id)
	switch {
	case err == sql.ErrNoRows:
		_, err = s.DB.ExecContext(ctx, `INSERT INTO customers (id, outlet_id, name, phone_norm, visits, lifetime_spend, last_visit)
			VALUES (?, ?, ?, ?, 1, ?, ?)`, NewID("c"), outletID, name, norm, spend, TimeStr(Now()))
		return err
	case err != nil:
		return err
	}
	_, err = s.DB.ExecContext(ctx, `UPDATE customers SET visits = visits + 1, lifetime_spend = lifetime_spend + ?, last_visit = ? WHERE id = ?`,
		spend, TimeStr(Now()), id)
	return err
}

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

func (s *Store) GetIdempotentResponse(ctx context.Context, key string) (int, []byte, bool, error) {
	var code int
	var body []byte
	err := s.DB.QueryRowContext(ctx, `SELECT response_code, response_body FROM idempotency_keys WHERE key = ?`, key).Scan(&code, &body)
	if err == sql.ErrNoRows {
		return 0, nil, false, nil
	}
	if err != nil {
		return 0, nil, false, err
	}
	return code, body, true, nil
}

func (s *Store) SaveIdempotentResponse(ctx context.Context, key string, code int, body []byte) error {
	if key == "" {
		return nil
	}
	_, err := s.DB.ExecContext(ctx, `INSERT INTO idempotency_keys (key, response_code, response_body, created_at)
		VALUES (?, ?, ?, ?) ON CONFLICT (key) DO NOTHING`, key, code, body, TimeStr(Now()))
	return err
}

// ---- KOTs ----

func (s *Store) InsertKOT(ctx context.Context, k *models.KOT) error {
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()
	if _, err := tx.ExecContext(ctx, `INSERT INTO kots (id, outlet_id, kot_number, order_id, status, waiter_id,
		waiter_name, table_number, order_type, note, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		k.ID, k.OutletID, k.KOTNumber, k.OrderID, k.Status, k.WaiterID, k.WaiterName, k.TableNumber,
		k.OrderType, k.Note, TimeStr(k.CreatedAt)); err != nil {
		return err
	}
	for _, it := range k.Items {
		if _, err := tx.ExecContext(ctx, `INSERT INTO kot_items (kot_id, order_item_id, name, quantity) VALUES (?, ?, ?, ?)`,
			k.ID, it.OrderItemID, it.Name, it.Quantity); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (s *Store) ListKOTs(ctx context.Context, outletID, status string) ([]models.KOT, error) {
	q := `SELECT id FROM kots WHERE outlet_id = ?`
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
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	out := []models.KOT{}
	for _, id := range ids {
		k, err := s.GetKOT(ctx, id)
		if err != nil {
			return nil, err
		}
		out = append(out, *k)
	}
	return out, nil
}

func (s *Store) GetKOT(ctx context.Context, id string) (*models.KOT, error) {
	k := &models.KOT{}
	var waiterID, waiterName, tableNumber, note sql.NullString
	var createdAt string
	err := s.DB.QueryRowContext(ctx, `SELECT id, outlet_id, kot_number, order_id, status, waiter_id, waiter_name,
		table_number, order_type, note, created_at FROM kots WHERE id = ?`, id).
		Scan(&k.ID, &k.OutletID, &k.KOTNumber, &k.OrderID, &k.Status, &waiterID, &waiterName,
			&tableNumber, &k.OrderType, &note, &createdAt)
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	k.WaiterID = nullIfEmpty(waiterID)
	k.WaiterName = nullIfEmpty(waiterName)
	k.TableNumber = nullIfEmpty(tableNumber)
	k.Note = nullIfEmpty(note)
	k.CreatedAt = ParseTime(createdAt)
	k.Items = []models.KOTItem{}
	rows, err := s.DB.QueryContext(ctx, `SELECT order_item_id, name, quantity FROM kot_items WHERE kot_id = ?`, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var it models.KOTItem
		if err := rows.Scan(&it.OrderItemID, &it.Name, &it.Quantity); err != nil {
			return nil, err
		}
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

// Shift sales helpers -------------------------------------------------------------

func (s *Store) AddShiftSales(ctx context.Context, shiftID, method string, amount int64) error {
	col := map[string]string{"cash": "cash_sales", "upi": "upi_sales", "card": "card_sales"}[method]
	if col == "" {
		return fmt.Errorf("unknown method %q", method)
	}
	_, err := s.DB.ExecContext(ctx, `UPDATE shifts SET `+col+` = `+col+` + ? WHERE id = ?`, amount, shiftID)
	return err
}

func (s *Store) AddShiftRefund(ctx context.Context, shiftID string, cash bool, amount int64) error {
	col := "refunds_digital"
	if cash {
		col = "refunds_cash"
	}
	_, err := s.DB.ExecContext(ctx, `UPDATE shifts SET `+col+` = `+col+` + ? WHERE id = ?`, amount, shiftID)
	return err
}

func (s *Store) AddShiftExpense(ctx context.Context, shiftID string, amount int64, sign int64) error {
	_, err := s.DB.ExecContext(ctx, `UPDATE shifts SET expenses = GREATEST(0, expenses + ?) WHERE id = ?`, sign*amount, shiftID)
	return err
}
