package store

import (
	"context"
	"database/sql"
	"strings"

	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/models"
)

// patchRow runs one UPDATE with the given column sets, scoped to the outlet
// and to live rows. No sets is a no-op; no row matched is 404.
func (s *Store) patchRow(ctx context.Context, table, id, outletID string, sets []string, args []any) error {
	if len(sets) == 0 {
		return nil
	}
	args = append(args, id, outletID)
	res, err := s.DB.ExecContext(ctx, `UPDATE `+table+` SET `+strings.Join(sets, ", ")+
		` WHERE id = ? AND outlet_id = ? AND is_deleted = 0`, args...)
	if err != nil {
		if isUniqueViolation(err) {
			return httpx.NewError(409, "duplicate", "Another record already uses that value")
		}
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return httpx.ErrNotFound
	}
	return nil
}

// optText stores "" as NULL for optional text columns.
func optText(v string) any {
	if strings.TrimSpace(v) == "" {
		return nil
	}
	return strings.TrimSpace(v)
}

// ---- Customers ----

func (s *Store) PatchCustomer(ctx context.Context, outletID, id string, p models.CustomerPatch) (*models.Customer, error) {
	var sets []string
	var args []any
	if p.Name != nil {
		if strings.TrimSpace(*p.Name) == "" {
			return nil, httpx.NewError(400, "invalid_customer", "Name is required")
		}
		sets, args = append(sets, "name = ?"), append(args, strings.TrimSpace(*p.Name))
	}
	if p.Phone != nil {
		norm := NormalizePhone(*p.Phone)
		if norm == "" {
			return nil, httpx.NewError(400, "invalid_customer", "A valid phone number is required")
		}
		sets, args = append(sets, "phone_norm = ?"), append(args, norm)
	}
	if p.Email != nil {
		sets, args = append(sets, "email = ?"), append(args, optText(*p.Email))
	}
	if p.Address != nil {
		sets, args = append(sets, "address = ?"), append(args, optText(*p.Address))
	}
	if err := s.patchRow(ctx, "customers", id, outletID, sets, args); err != nil {
		if e, ok := err.(*httpx.AppError); ok && e.Code == "duplicate" {
			return nil, httpx.NewError(409, "customer_exists", "Another customer already has this phone number")
		}
		return nil, err
	}
	return s.GetCustomerByID(ctx, outletID, id)
}

// DeleteCustomer hides a customer. One who still owes money can't be removed.
func (s *Store) DeleteCustomer(ctx context.Context, outletID, id string) error {
	c, err := s.GetCustomerByID(ctx, outletID, id)
	if err != nil {
		return err
	}
	if c.Outstanding > 0 {
		return httpx.NewError(409, "credit_outstanding", "This customer still owes money. Settle the credit first.")
	}
	return s.patchRow(ctx, "customers", id, outletID, []string{"is_deleted = 1"}, nil)
}

// ---- Suppliers ----

func (s *Store) PatchSupplier(ctx context.Context, outletID, id string, p models.SupplierPatch) (*models.Supplier, error) {
	var sets []string
	var args []any
	if p.Name != nil {
		if strings.TrimSpace(*p.Name) == "" {
			return nil, httpx.NewError(400, "invalid_supplier", "Supplier name is required")
		}
		sets, args = append(sets, "name = ?"), append(args, strings.TrimSpace(*p.Name))
	}
	if p.Mobile != nil {
		sets, args = append(sets, "mobile = ?"), append(args, strings.TrimSpace(*p.Mobile))
	}
	if p.Email != nil {
		sets, args = append(sets, "email = ?"), append(args, optText(*p.Email))
	}
	if p.Category != nil {
		sets, args = append(sets, "category = ?"), append(args, optText(*p.Category))
	}
	if err := s.patchRow(ctx, "suppliers", id, outletID, sets, args); err != nil {
		return nil, err
	}
	return s.GetSupplier(ctx, id)
}

// DeleteSupplier hides a supplier. One we still owe can't be removed.
func (s *Store) DeleteSupplier(ctx context.Context, outletID, id string) error {
	sup, err := s.GetSupplier(ctx, id)
	if err != nil || sup.OutletID != outletID {
		return httpx.ErrNotFound
	}
	if sup.Outstanding > 0 {
		return httpx.NewError(409, "supplier_outstanding", "You still owe this supplier. Pay the balance first.")
	}
	return s.patchRow(ctx, "suppliers", id, outletID, []string{"is_deleted = 1"}, nil)
}

// ---- Inventory ----

func (s *Store) GetInventoryItem(ctx context.Context, outletID, id string) (*models.InventoryItem, error) {
	item, err := scanInventoryItem(s.DB.QueryRowContext(ctx,
		`SELECT id, outlet_id, name, unit, stock, min_stock, cost_paise, batch_no, rack_no, purchased_at
		 FROM inventory_items WHERE id = ? AND outlet_id = ? AND is_deleted = 0`, id, outletID))
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	return item, err
}

func (s *Store) PatchInventoryItem(ctx context.Context, outletID, id string, p models.InventoryPatch) (*models.InventoryItem, error) {
	var sets []string
	var args []any
	if p.Name != nil {
		if strings.TrimSpace(*p.Name) == "" {
			return nil, httpx.NewError(400, "invalid_item", "Name is required")
		}
		sets, args = append(sets, "name = ?"), append(args, strings.TrimSpace(*p.Name))
	}
	if p.Unit != nil {
		if strings.TrimSpace(*p.Unit) == "" {
			return nil, httpx.NewError(400, "invalid_item", "Unit is required")
		}
		sets, args = append(sets, "unit = ?"), append(args, strings.TrimSpace(*p.Unit))
	}
	if p.MinStock != nil {
		if *p.MinStock < 0 {
			return nil, httpx.NewError(400, "invalid_item", "Minimum stock cannot be negative")
		}
		sets, args = append(sets, "min_stock = ?"), append(args, *p.MinStock)
	}
	if p.CostPaise != nil {
		if *p.CostPaise < 0 {
			return nil, httpx.NewError(400, "invalid_item", "Cost cannot be negative")
		}
		sets, args = append(sets, "cost_paise = ?"), append(args, *p.CostPaise)
	}
	if p.BatchNo != nil {
		sets, args = append(sets, "batch_no = ?"), append(args, optText(*p.BatchNo))
	}
	if p.RackNo != nil {
		sets, args = append(sets, "rack_no = ?"), append(args, optText(*p.RackNo))
	}
	if err := s.patchRow(ctx, "inventory_items", id, outletID, sets, args); err != nil {
		return nil, err
	}
	return s.GetInventoryItem(ctx, outletID, id)
}

func (s *Store) DeleteInventoryItem(ctx context.Context, outletID, id string) error {
	return s.patchRow(ctx, "inventory_items", id, outletID, []string{"is_deleted = 1"}, nil)
}

// ---- Expenses ----

// PatchExpense edits an expense; an amount change on a cash expense moves
// the drawer of the shift it was booked in by the difference. Returns the
// expense and that shift id ("" if none).
func (s *Store) PatchExpense(ctx context.Context, id string, p models.ExpensePatch) (*models.Expense, string, error) {
	var out *models.Expense
	var shiftID string
	err := s.withTx(ctx, func(tx *sql.Tx) error {
		e, sh, err := s.getExpense(ctx, tx, id, true)
		if err != nil {
			return err
		}
		shiftID = sh
		var sets []string
		var args []any
		if p.Title != nil {
			if strings.TrimSpace(*p.Title) == "" {
				return httpx.NewError(400, "invalid_expense", "Title is required")
			}
			sets, args = append(sets, "title = ?"), append(args, strings.TrimSpace(*p.Title))
		}
		if p.Category != nil {
			sets, args = append(sets, "category = ?"), append(args, *p.Category)
		}
		if p.Vendor != nil {
			sets, args = append(sets, "vendor = ?"), append(args, optText(*p.Vendor))
		}
		if p.Reference != nil {
			sets, args = append(sets, "reference = ?"), append(args, optText(*p.Reference))
		}
		if p.Note != nil {
			sets, args = append(sets, "note = ?"), append(args, optText(*p.Note))
		}
		if p.Amount != nil {
			if *p.Amount <= 0 {
				return httpx.ErrInvalidAmount
			}
			sets, args = append(sets, "amount = ?"), append(args, *p.Amount)
			if delta := *p.Amount - e.Amount; delta != 0 && shiftID != "" && IsCashMethod(e.Method) {
				if _, err := tx.ExecContext(ctx, `UPDATE shifts SET expenses = GREATEST(0, expenses + ?) WHERE id = ?`,
					delta, shiftID); err != nil {
					return err
				}
			}
		}
		if len(sets) > 0 {
			args = append(args, id)
			if _, err := tx.ExecContext(ctx, `UPDATE expenses SET `+strings.Join(sets, ", ")+` WHERE id = ?`, args...); err != nil {
				return err
			}
		}
		out, _, err = s.getExpense(ctx, tx, id, false)
		return err
	})
	if p.Amount == nil {
		shiftID = ""
	}
	return out, shiftID, err
}

// ---- Orders ----

// OrderHasKOT reports whether the kitchen already received any KOT for it.
func (s *Store) OrderHasKOT(ctx context.Context, orderID string) (bool, error) {
	var n int
	err := s.DB.QueryRowContext(ctx, `SELECT COUNT(*) FROM kots WHERE order_id = ?`, orderID).Scan(&n)
	return n > 0, err
}

// CancelOpenOrder voids an order nobody has paid for: the order becomes
// cancelled, its open KOTs are cancelled and its table (and any table merged
// into it) is freed.
func (s *Store) CancelOpenOrder(ctx context.Context, orderID, reason string) (*models.Order, error) {
	var out *models.Order
	err := s.withTx(ctx, func(tx *sql.Tx) error {
		o, err := s.getOrderQ(ctx, tx, orderID, true)
		if err != nil {
			return err
		}
		if IsClosedStatus(o.Status) {
			return ErrOrderClosed
		}
		if len(o.Payments) > 0 {
			return httpx.NewError(409, "order_paid", "This order has a payment. Refund it instead.")
		}
		note := "Cancelled"
		if r := strings.TrimSpace(reason); r != "" {
			note += ": " + r
		}
		if o.OrderNote != nil && *o.OrderNote != "" {
			note = *o.OrderNote + " · " + note
		}
		if _, err := tx.ExecContext(ctx, `UPDATE orders SET status = 'cancelled', order_note = ?, updated_at = ? WHERE id = ?`,
			note, TimeStr(Now()), orderID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE kots SET status = 'cancelled'
			WHERE order_id = ? AND status IN ('new','preparing','ready')`, orderID); err != nil {
			return err
		}
		if o.TableID != nil {
			if _, err := tx.ExecContext(ctx, `UPDATE tables SET merged_with_table_id = NULL, status = 'available',
				active_order_id = NULL, current_amount = 0, guest_count = 0, running_minutes = 0, assigned_waiter_id = NULL
				WHERE merged_with_table_id = ?`, *o.TableID); err != nil {
				return err
			}
			if _, err := tx.ExecContext(ctx, `UPDATE tables SET status = 'available', active_order_id = NULL,
				current_amount = 0, running_minutes = 0, guest_count = 0, assigned_waiter_id = NULL
				WHERE id = ? AND active_order_id = ?`, *o.TableID, orderID); err != nil {
				return err
			}
		}
		out, err = s.getOrderQ(ctx, tx, orderID, false)
		return err
	})
	return out, err
}
