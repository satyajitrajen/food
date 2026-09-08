package store

import (
	"context"
	"database/sql"
	"math"
	"strconv"
	"strings"

	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/models"
)

// ---- Shifts ----

func scanShift(row interface{ Scan(...any) error }) (*models.Shift, error) {
	sh := &models.Shift{}
	var closedAt, openingNotes, counted, closingNotes sql.NullString
	var startedAt string
	var status string
	if err := row.Scan(&sh.ID, &sh.OutletID, &sh.StaffID, &sh.StaffName, &startedAt, &closedAt,
		&sh.OpeningPaise, &openingNotes, &sh.CashSales, &sh.UPIsales, &sh.CardSales,
		&sh.RefundsCash, &sh.RefundsDigital, &sh.Expenses, &sh.CashIn, &sh.CashOut,
		&counted, &closingNotes, &status); err != nil {
		return nil, err
	}
	sh.StartedAt = ParseTime(startedAt)
	if closedAt.Valid {
		t := ParseTime(closedAt.String)
		sh.ClosedAt = &t
	}
	sh.OpeningNotes = nullIfEmpty(openingNotes)
	if counted.Valid {
		v := parsePaise(counted.String)
		sh.CountedPaise = &v
	}
	sh.ClosingNotes = nullIfEmpty(closingNotes)
	sh.Status = status
	return sh, nil
}

func parsePaise(s string) int64 {
	var v int64
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			continue
		}
		v = v*10 + int64(s[i]-'0')
	}
	return v
}

func (s *Store) GetCurrentShift(ctx context.Context, outletID string) (*models.Shift, error) {
	row := s.DB.QueryRowContext(ctx, `SELECT id, outlet_id, staff_id, staff_name, started_at, closed_at,
		opening_paise, opening_notes, cash_sales, upi_sales, card_sales, refunds_cash, refunds_digital,
		expenses, cash_in, cash_out, counted_paise, closing_notes, status
		FROM shifts WHERE outlet_id = ? AND status = 'open'`, outletID)
	sh, err := scanShift(row)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return sh, err
}

func (s *Store) GetShift(ctx context.Context, id string) (*models.Shift, error) {
	row := s.DB.QueryRowContext(ctx, `SELECT id, outlet_id, staff_id, staff_name, started_at, closed_at,
		opening_paise, opening_notes, cash_sales, upi_sales, card_sales, refunds_cash, refunds_digital,
		expenses, cash_in, cash_out, counted_paise, closing_notes, status
		FROM shifts WHERE id = ?`, id)
	sh, err := scanShift(row)
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	return sh, err
}

func (s *Store) ListShifts(ctx context.Context, outletID string, limit int) ([]models.Shift, error) {
	rows, err := s.DB.QueryContext(ctx, `SELECT id, outlet_id, staff_id, staff_name, started_at, closed_at,
		opening_paise, opening_notes, cash_sales, upi_sales, card_sales, refunds_cash, refunds_digital,
		expenses, cash_in, cash_out, counted_paise, closing_notes, status
		FROM shifts WHERE outlet_id = ? ORDER BY started_at DESC LIMIT ?`, outletID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []models.Shift{}
	for {
		sh, err := scanShift(rows)
		if err != nil {
			break
		}
		out = append(out, *sh)
	}
	return out, nil
}

func (s *Store) OpenShift(ctx context.Context, outletID, staffID, staffName string, req models.ShiftOpenReq) (*models.Shift, error) {
	id := NewID("sh")
	_, err := s.DB.ExecContext(ctx, `INSERT INTO shifts (id, outlet_id, staff_id, staff_name, started_at,
		opening_paise, opening_notes, status) VALUES (?, ?, ?, ?, ?, ?, ?, 'open')`,
		id, outletID, staffID, staffName, TimeStr(Now()), req.OpeningPaise, req.Notes)
	if err != nil {
		return nil, err
	}
	if req.Denominations != nil {
		if err := s.saveDenominations(ctx, id, "open", req.Denominations); err != nil {
			return nil, err
		}
	}
	return s.GetShift(ctx, id)
}

func (s *Store) saveDenominations(ctx context.Context, shiftID, kind string, d *models.CashDenominations) error {
	_, err := s.DB.ExecContext(ctx, `INSERT INTO shift_denominations (shift_id, kind, d500, d200, d100, d50, d20, d10)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT (shift_id, kind) DO UPDATE SET
			d500 = EXCLUDED.d500, d200 = EXCLUDED.d200, d100 = EXCLUDED.d100,
			d50 = EXCLUDED.d50, d20 = EXCLUDED.d20, d10 = EXCLUDED.d10`, shiftID, kind, d.D500, d.D200, d.D100, d.D50, d.D20, d.D10)
	return err
}

func (s *Store) CloseShift(ctx context.Context, shiftID string, req models.ShiftCloseReq) (*models.Shift, error) {
	res, err := s.DB.ExecContext(ctx, `UPDATE shifts SET closed_at = ?, counted_paise = ?, closing_notes = ?, status = 'closed'
		WHERE id = ? AND status = 'open'`, TimeStr(Now()), req.CountedPaise, req.Notes, shiftID)
	if err != nil {
		return nil, err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return nil, httpx.NewError(409, "invalid_state", "Shift is not open")
	}
	if req.Denominations != nil {
		if err := s.saveDenominations(ctx, shiftID, "close", req.Denominations); err != nil {
			return nil, err
		}
	}
	return s.GetShift(ctx, shiftID)
}

// ---- Cash movements ----

func (s *Store) AddCashMove(ctx context.Context, shiftID, staffID, staffName, moveType string, amount int64, reason string, reference *string) (*models.CashTransaction, error) {
	id := NewID("cx")
	_, err := s.DB.ExecContext(ctx, `INSERT INTO cash_transactions (id, shift_id, type, amount, reason, reference, staff_id, staff_name, ts)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`, id, shiftID, moveType, amount, reason, reference, staffID, staffName, TimeStr(Now()))
	if err != nil {
		return nil, err
	}
	col := "cash_in"
	if moveType == "cash_out" {
		col = "cash_out"
	}
	if _, err := s.DB.ExecContext(ctx, `UPDATE shifts SET `+col+` = `+col+` + ? WHERE id = ?`, amount, shiftID); err != nil {
		return nil, err
	}
	return &models.CashTransaction{
		ID: id, Amount: amount, Reason: reason, Reference: reference, StaffID: &staffID,
	}, nil
}

// ---- Expenses ----

func (s *Store) ListExpenses(ctx context.Context, outletID, rangeKey string) ([]models.Expense, error) {
	q := `SELECT id, outlet_id, title, category, amount, method, vendor, reference, note, ts, created_by
	      FROM expenses WHERE outlet_id = ?`
	if rangeKey == "today" {
		q += ` AND ts::date = CURRENT_DATE`
	} else if rangeKey == "month" {
		q += ` AND to_char(ts::timestamp, 'YYYY-MM') = to_char(now(), 'YYYY-MM')`
	}
	q += ` ORDER BY ts DESC LIMIT 500`
	rows, err := s.DB.QueryContext(ctx, q, outletID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []models.Expense{}
	for rows.Next() {
		var e models.Expense
		var vendor, reference, note, createdBy sql.NullString
		var ts string
		if err := rows.Scan(&e.ID, &e.OutletID, &e.Title, &e.Category, &e.Amount, &e.Method,
			&vendor, &reference, &note, &ts, &createdBy); err != nil {
			return nil, err
		}
		e.Vendor = nullIfEmpty(vendor)
		e.Reference = nullIfEmpty(reference)
		e.Note = nullIfEmpty(note)
		e.CreatedBy = nullIfEmpty(createdBy)
		e.Ts = ParseTime(ts)
		out = append(out, e)
	}
	return out, rows.Err()
}

func (s *Store) CreateExpense(ctx context.Context, outletID string, req models.ExpenseCreate, createdBy *string) (*models.Expense, error) {
	if req.Amount <= 0 {
		return nil, httpx.ErrInvalidAmount
	}
	id := NewID("exp")
	_, err := s.DB.ExecContext(ctx, `INSERT INTO expenses (id, outlet_id, title, category, amount, method, vendor, reference, note, ts, created_by)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		id, outletID, req.Title, req.Category, req.Amount, req.Method, req.Vendor, req.Reference, req.Note, TimeStr(Now()), createdBy)
	if err != nil {
		return nil, err
	}
	return &models.Expense{ID: id, OutletID: outletID, Title: req.Title, Category: req.Category,
		Amount: req.Amount, Method: req.Method, Vendor: req.Vendor, Reference: req.Reference,
		Note: req.Note, Ts: Now(), CreatedBy: createdBy}, nil
}

func (s *Store) DeleteExpense(ctx context.Context, id string) (*models.Expense, error) {
	e := &models.Expense{}
	var vendor, reference, note, createdBy sql.NullString
	var ts string
	err := s.DB.QueryRowContext(ctx, `SELECT id, outlet_id, title, category, amount, method, vendor, reference, note, ts, created_by
		FROM expenses WHERE id = ?`, id).
		Scan(&e.ID, &e.OutletID, &e.Title, &e.Category, &e.Amount, &e.Method, &vendor, &reference, &note, &ts, &createdBy)
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	if _, err := s.DB.ExecContext(ctx, `DELETE FROM expenses WHERE id = ?`, id); err != nil {
		return nil, err
	}
	return e, nil
}

func (s *Store) SumExpenses(ctx context.Context, outletID, rangeKey string) (int64, error) {
	q := `SELECT COALESCE(SUM(amount),0) FROM expenses WHERE outlet_id = ?`
	if rangeKey == "today" {
		q += ` AND ts::date = CURRENT_DATE`
	} else if rangeKey == "month" {
		q += ` AND to_char(ts::timestamp, 'YYYY-MM') = to_char(now(), 'YYYY-MM')`
	}
	var sum int64
	err := s.DB.QueryRowContext(ctx, q, outletID).Scan(&sum)
	return sum, err
}

// ---- Customers ----

func (s *Store) ListCustomers(ctx context.Context, outletID, q string) ([]models.Customer, error) {
	query := `SELECT id, outlet_id, name, phone_norm, email, address, visits, lifetime_spend, outstanding_paise, last_visit
	          FROM customers WHERE outlet_id = ?`
	args := []any{outletID}
	if q != "" {
		query += ` AND (name LIKE ? OR phone_norm LIKE ?)`
		like := "%" + q + "%"
		args = append(args, like, like)
	}
	query += ` ORDER BY lifetime_spend DESC LIMIT 200`
	rows, err := s.DB.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []models.Customer{}
	for rows.Next() {
		var c models.Customer
		var email, address, lastVisit sql.NullString
		if err := rows.Scan(&c.ID, &c.OutletID, &c.Name, &c.PhoneNorm, &email, &address,
			&c.Visits, &c.LifetimeSpend, &c.Outstanding, &lastVisit); err != nil {
			return nil, err
		}
		c.Email = nullIfEmpty(email)
		c.Address = nullIfEmpty(address)
		if lastVisit.Valid {
			t := ParseTime(lastVisit.String)
			c.LastVisit = &t
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func (s *Store) CreateCustomer(ctx context.Context, outletID string, req models.CustomerCreate) (*models.Customer, error) {
	norm := NormalizePhone(req.Phone)
	if norm == "" || req.Name == "" {
		return nil, httpx.NewError(400, "invalid_customer", "Name and phone are required")
	}
	id := NewID("c")
	var email, address any
	if req.Email != nil {
		email = *req.Email
	}
	if req.Address != nil {
		address = *req.Address
	}
	_, err := s.DB.ExecContext(ctx, `INSERT INTO customers (id, outlet_id, name, phone_norm, email, address)
		VALUES (?, ?, ?, ?, ?, ?)`, id, outletID, req.Name, norm, email, address)
	if err != nil {
		return nil, err
	}
	return &models.Customer{ID: id, OutletID: outletID, Name: req.Name, PhoneNorm: norm,
		Email: req.Email, Address: req.Address}, nil
}

// ---- Inventory ----

func (s *Store) ListInventory(ctx context.Context, outletID string, lowOnly bool) ([]models.InventoryItem, error) {
	q := `SELECT id, outlet_id, name, unit, stock, min_stock, cost_paise FROM inventory_items WHERE outlet_id = ?`
	if lowOnly {
		q += ` AND stock <= min_stock`
	}
	q += ` ORDER BY name`
	rows, err := s.DB.QueryContext(ctx, q, outletID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []models.InventoryItem{}
	for rows.Next() {
		var i models.InventoryItem
		if err := rows.Scan(&i.ID, &i.OutletID, &i.Name, &i.Unit, &i.Stock, &i.MinStock, &i.CostPaise); err != nil {
			return nil, err
		}
		out = append(out, i)
	}
	return out, rows.Err()
}

func (s *Store) AdjustStock(ctx context.Context, outletID, itemID string, delta float64, reason, staffID, staffName string) (*models.InventoryItem, error) {
	if delta == 0 {
		return nil, httpx.NewError(400, "invalid_delta", "Delta must be non-zero")
	}
	var stock float64
	err := s.DB.QueryRowContext(ctx, `SELECT stock FROM inventory_items WHERE id = ? AND outlet_id = ?`, itemID, outletID).Scan(&stock)
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	next := math.Max(0, stock+delta)
	if _, err := s.DB.ExecContext(ctx, `UPDATE inventory_items SET stock = ? WHERE id = ?`, next, itemID); err != nil {
		return nil, err
	}
	if _, err := s.DB.ExecContext(ctx, `INSERT INTO stock_adjustments (id, item_id, delta, reason, staff_id, staff_name, ts)
		VALUES (?, ?, ?, ?, ?, ?, ?)`, NewID("sa"), itemID, delta, reason, staffID, staffName, TimeStr(Now())); err != nil {
		return nil, err
	}
	var item models.InventoryItem
	err = s.DB.QueryRowContext(ctx, `SELECT id, outlet_id, name, unit, stock, min_stock, cost_paise FROM inventory_items WHERE id = ?`, itemID).
		Scan(&item.ID, &item.OutletID, &item.Name, &item.Unit, &item.Stock, &item.MinStock, &item.CostPaise)
	return &item, err
}

func (s *Store) CreateInventoryItem(ctx context.Context, outletID string, item models.InventoryItem) (*models.InventoryItem, error) {
	id := NewID("inv")
	_, err := s.DB.ExecContext(ctx, `INSERT INTO inventory_items (id, outlet_id, name, unit, stock, min_stock, cost_paise)
		VALUES (?, ?, ?, ?, ?, ?, ?)`, id, outletID, item.Name, item.Unit, item.Stock, item.MinStock, item.CostPaise)
	if err != nil {
		return nil, err
	}
	item.ID = id
	return &item, nil
}

// ---- Suppliers & Purchases ----

func (s *Store) ListSuppliers(ctx context.Context, outletID string) ([]map[string]any, error) {
	rows, err := s.DB.QueryContext(ctx, `SELECT id, name, mobile, email, category, outstanding FROM suppliers WHERE outlet_id = ?`, outletID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var id, name, mobile string
		var email, category sql.NullString
		var outstanding int64
		if err := rows.Scan(&id, &name, &mobile, &email, &category, &outstanding); err != nil {
			return nil, err
		}
		out = append(out, map[string]any{"id": id, "name": name, "mobile": mobile,
			"email": nullIfEmpty(email), "category": nullIfEmpty(category), "outstanding_paise": outstanding})
	}
	return out, rows.Err()
}

func (s *Store) ListPurchases(ctx context.Context, outletID string) ([]map[string]any, error) {
	rows, err := s.DB.QueryContext(ctx, `SELECT id, invoice_no, supplier_name, ts, total_paise, status, summary
		FROM purchases WHERE outlet_id = ? ORDER BY ts DESC LIMIT 200`, outletID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var id, invoiceNo, supplierName, ts, status, summary string
		var total int64
		if err := rows.Scan(&id, &invoiceNo, &supplierName, &ts, &total, &status, &summary); err != nil {
			return nil, err
		}
		out = append(out, map[string]any{"id": id, "invoice_no": invoiceNo, "supplier_name": supplierName,
			"ts": ts, "total_paise": total, "status": status, "summary": summary})
	}
	return out, rows.Err()
}

func (s *Store) CreateSupplier(ctx context.Context, outletID string, req models.SupplierCreate) (*models.Supplier, error) {
	if req.Name == "" {
		return nil, httpx.NewError(400, "invalid_supplier", "Supplier name is required")
	}
	id := NewID("sup")
	var email, category any
	if req.Email != nil {
		email = *req.Email
	}
	if req.Category != nil {
		category = *req.Category
	}
	_, err := s.DB.ExecContext(ctx, `INSERT INTO suppliers (id, outlet_id, name, mobile, email, category, outstanding)
		VALUES (?, ?, ?, ?, ?, ?, 0)`, id, outletID, req.Name, req.Mobile, email, category)
	if err != nil {
		return nil, err
	}
	return &models.Supplier{ID: id, OutletID: outletID, Name: req.Name, Mobile: req.Mobile,
		Email: req.Email, Category: req.Category}, nil
}

// CreatePurchase records a purchase and, for each line with an inventory
// item, posts stock intake through the adjustment log. A `pending` purchase
// increases the supplier's outstanding balance.
func (s *Store) CreatePurchase(ctx context.Context, outletID string, req models.PurchaseCreate, staffID, staffName string) (*models.Purchase, error) {
	if req.InvoiceNo == "" {
		return nil, httpx.NewError(400, "invalid_purchase", "invoice_no is required")
	}
	if req.TotalPaise < 0 {
		return nil, httpx.ErrInvalidAmount
	}
	if req.Status != "paid" && req.Status != "pending" {
		return nil, httpx.NewError(400, "invalid_status", "status must be paid or pending")
	}
	supplierName := ""
	supplierID := req.SupplierID
	if supplierID != nil && *supplierID != "" {
		var name string
		err := s.DB.QueryRowContext(ctx, `SELECT name FROM suppliers WHERE id = ? AND outlet_id = ?`, *supplierID, outletID).Scan(&name)
		if err == sql.ErrNoRows {
			return nil, httpx.NewError(400, "invalid_supplier", "Supplier not found in this outlet")
		}
		if err != nil {
			return nil, err
		}
		supplierName = name
	} else {
		supplierID = nil
	}

	summary := buildPurchaseSummary(req.Items)
	id := NewID("pur")
	ts := Now()

	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback() }()

	if _, err := tx.ExecContext(ctx, `INSERT INTO purchases (id, outlet_id, invoice_no, supplier_id, supplier_name, ts, total_paise, status, summary)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		id, outletID, req.InvoiceNo, supplierID, supplierName, TimeStr(ts), req.TotalPaise, req.Status, summary); err != nil {
		return nil, err
	}
	for _, line := range req.Items {
		if line.Qty == 0 {
			continue
		}
		var stock float64
		var name string
		err := tx.QueryRowContext(ctx, `SELECT stock, name FROM inventory_items WHERE id = ? AND outlet_id = ?`, line.InventoryItemID, outletID).Scan(&stock, &name)
		if err == sql.ErrNoRows {
			return nil, httpx.NewError(400, "invalid_item", "Inventory item not found in this outlet")
		}
		if err != nil {
			return nil, err
		}
		displayName := line.Name
		if displayName == "" {
			displayName = name
		}
		if _, err := tx.ExecContext(ctx, `UPDATE inventory_items SET stock = stock + ?, cost_paise = ? WHERE id = ?`,
			line.Qty, line.UnitCostPaise, line.InventoryItemID); err != nil {
			return nil, err
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO stock_adjustments (id, item_id, delta, reason, staff_id, staff_name, ts)
			VALUES (?, ?, ?, ?, ?, ?, ?)`,
			NewID("sa"), line.InventoryItemID, line.Qty, "Purchase "+req.InvoiceNo, staffID, staffName, TimeStr(ts)); err != nil {
			return nil, err
		}
	}
	if supplierID != nil && req.Status == "pending" {
		if _, err := tx.ExecContext(ctx, `UPDATE suppliers SET outstanding = outstanding + ? WHERE id = ?`, req.TotalPaise, *supplierID); err != nil {
			return nil, err
		}
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return &models.Purchase{
		ID: id, OutletID: outletID, InvoiceNo: req.InvoiceNo, SupplierID: supplierID,
		SupplierName: supplierName, Ts: ts, TotalPaise: req.TotalPaise,
		Status: req.Status, Summary: summary, Items: req.Items,
	}, nil
}

// PatchPurchaseStatus is the pending→paid settlement: it reduces the
// supplier's outstanding balance by the purchase total.
func (s *Store) PatchPurchaseStatus(ctx context.Context, purchaseID, newStatus string) (*models.Purchase, error) {
	p, err := s.getPurchaseRow(ctx, purchaseID)
	if err != nil {
		return nil, err
	}
	if p.Status == newStatus {
		return p, nil
	}
	if p.Status == "paid" && newStatus == "pending" {
		return nil, httpx.NewError(409, "invalid_state", "A paid purchase cannot go back to pending")
	}
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback() }()
	res, err := tx.ExecContext(ctx, `UPDATE purchases SET status = ? WHERE id = ? AND status = ?`, newStatus, purchaseID, p.Status)
	if err != nil {
		return nil, err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return nil, httpx.ErrConflict
	}
	if p.SupplierID != nil {
		if newStatus == "paid" {
			if _, err := tx.ExecContext(ctx, `UPDATE suppliers SET outstanding = GREATEST(0, outstanding - ?) WHERE id = ?`, p.TotalPaise, *p.SupplierID); err != nil {
				return nil, err
			}
		} else if _, err := tx.ExecContext(ctx, `UPDATE suppliers SET outstanding = outstanding + ? WHERE id = ?`, p.TotalPaise, *p.SupplierID); err != nil {
			return nil, err
		}
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	p.Status = newStatus
	return p, nil
}

func (s *Store) getPurchaseRow(ctx context.Context, id string) (*models.Purchase, error) {
	var p models.Purchase
	var supplierID, ts string
	var supplierName, status, summary string
	err := s.DB.QueryRowContext(ctx, `SELECT id, outlet_id, invoice_no, supplier_id, supplier_name, ts, total_paise, status, summary
		FROM purchases WHERE id = ?`, id).
		Scan(&p.ID, &p.OutletID, &p.InvoiceNo, &supplierID, &supplierName, &ts, &p.TotalPaise, &status, &summary)
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	if supplierID != "" {
		p.SupplierID = &supplierID
	}
	p.SupplierName = supplierName
	p.Status = status
	p.Summary = summary
	p.Ts = ParseTime(ts)
	return &p, nil
}

func buildPurchaseSummary(items []models.PurchaseLine) string {
	if len(items) == 0 {
		return ""
	}
	parts := make([]string, 0, len(items))
	for _, it := range items {
		name := it.Name
		if name == "" {
			name = it.InventoryItemID
		}
		parts = append(parts, strconv.FormatFloat(it.Qty, 'f', -1, 64)+" x "+name)
	}
	return strings.Join(parts, ", ")
}

// ---- Stock adjustment log ----

func (s *Store) ListStockAdjustments(ctx context.Context, outletID, itemID string, limit int) ([]models.StockAdjustmentEntry, error) {
	q := `SELECT sa.id, sa.item_id, i.name, sa.delta, sa.reason, sa.staff_id, sa.staff_name, sa.ts
	      FROM stock_adjustments sa JOIN inventory_items i ON i.id = sa.item_id
	      WHERE i.outlet_id = ?`
	args := []any{outletID}
	if itemID != "" {
		q += ` AND sa.item_id = ?`
		args = append(args, itemID)
	}
	if limit <= 0 {
		limit = 100
	}
	q += ` ORDER BY sa.ts DESC LIMIT ?`
	args = append(args, limit)
	rows, err := s.DB.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []models.StockAdjustmentEntry{}
	for rows.Next() {
		var e models.StockAdjustmentEntry
		var staffID, staffName sql.NullString
		var ts string
		if err := rows.Scan(&e.ID, &e.ItemID, &e.ItemName, &e.Delta, &e.Reason, &staffID, &staffName, &ts); err != nil {
			return nil, err
		}
		if staffID.Valid {
			e.StaffID = &staffID.String
		}
		if staffName.Valid {
			e.StaffName = &staffName.String
		}
		e.Ts = ParseTime(ts)
		out = append(out, e)
	}
	return out, rows.Err()
}

// ---- Customer credit (FR-C1) ----

// BookCustomerCredit records a credit sale (outstanding up) or settlement
// (outstanding down) and appends the audit log row.
func (s *Store) BookCustomerCredit(ctx context.Context, outletID, customerID, kind string, amount int64, reason, staffID, staffName string) (*models.Customer, error) {
	if amount <= 0 {
		return nil, httpx.ErrInvalidAmount
	}
	if kind != "sale" && kind != "settlement" {
		return nil, httpx.NewError(400, "invalid_type", "kind must be sale or settlement")
	}
	if reason == "" {
		return nil, httpx.NewError(400, "missing_reason", "A reason is required for credit movements")
	}
	var outstanding int64
	err := s.DB.QueryRowContext(ctx, `SELECT outstanding_paise FROM customers WHERE id = ? AND outlet_id = ?`, customerID, outletID).Scan(&outstanding)
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	next := outstanding
	switch kind {
	case "sale":
		next = outstanding + amount
	case "settlement":
		if amount > outstanding {
			return nil, httpx.NewError(400, "settlement_exceeds_outstanding",
				"Settlement exceeds the customer's outstanding balance")
		}
		next = outstanding - amount
	}
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback() }()
	if _, err := tx.ExecContext(ctx, `UPDATE customers SET outstanding_paise = ? WHERE id = ?`, next, customerID); err != nil {
		return nil, err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO customer_credit_log (id, outlet_id, customer_id, kind, amount_paise, reason, staff_id, staff_name, ts)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`, NewID("ccl"), outletID, customerID, kind, amount, reason, staffID, staffName, TimeStr(Now())); err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	c, err := s.GetCustomerByID(ctx, outletID, customerID)
	if err != nil {
		return nil, err
	}
	return c, nil
}

func (s *Store) GetCustomerByID(ctx context.Context, outletID, id string) (*models.Customer, error) {
	var c models.Customer
	var email, address, lastVisit sql.NullString
	err := s.DB.QueryRowContext(ctx, `SELECT id, outlet_id, name, phone_norm, email, address, visits, lifetime_spend, outstanding_paise, last_visit
		FROM customers WHERE id = ? AND outlet_id = ?`, id, outletID).
		Scan(&c.ID, &c.OutletID, &c.Name, &c.PhoneNorm, &email, &address, &c.Visits, &c.LifetimeSpend, &c.Outstanding, &lastVisit)
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	c.Email = nullIfEmpty(email)
	c.Address = nullIfEmpty(address)
	if lastVisit.Valid {
		t := ParseTime(lastVisit.String)
		c.LastVisit = &t
	}
	return &c, nil
}

func (s *Store) ListCustomerCreditLog(ctx context.Context, outletID, customerID string, limit int) ([]models.CustomerCreditEntry, error) {
	if limit <= 0 {
		limit = 100
	}
	rows, err := s.DB.QueryContext(ctx, `SELECT id, outlet_id, customer_id, kind, amount_paise, reason, staff_id, staff_name, ts
		FROM customer_credit_log WHERE outlet_id = ? AND customer_id = ? ORDER BY ts DESC LIMIT ?`, outletID, customerID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []models.CustomerCreditEntry{}
	for rows.Next() {
		var e models.CustomerCreditEntry
		var staffID, staffName sql.NullString
		var ts string
		if err := rows.Scan(&e.ID, &e.OutletID, &e.CustomerID, &e.Kind, &e.Amount, &e.Reason, &staffID, &staffName, &ts); err != nil {
			return nil, err
		}
		if staffID.Valid {
			e.StaffID = &staffID.String
		}
		if staffName.Valid {
			e.StaffName = &staffName.String
		}
		e.Ts = ParseTime(ts)
		out = append(out, e)
	}
	return out, rows.Err()
}
