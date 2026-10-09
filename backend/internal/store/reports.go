package store

// Report aggregates computed in SQL over a paid_at window [from, to). Every
// query is scoped by outlet + the (outlet_id, paid_at) index; nothing loads
// whole order histories into memory.

import (
	"context"
	"time"

	"foodpos/backend/internal/models"
)

// paidWindow is the shared WHERE fragment (alias o) + its args.
const paidWindow = `o.outlet_id = ? AND o.status IN ('completed','refunded') AND o.paid_at >= ? AND o.paid_at < ?`

func windowArgs(outletID string, from, to time.Time) []any {
	return []any{outletID, TimeStr(from), TimeStr(to)}
}

// FillDashboard computes the sales aggregates of rep for orders paid in
// [from, to) and the refunds/expenses dated in the same window.
func (s *Store) FillDashboard(ctx context.Context, outletID string, from, to time.Time, rep *models.DashboardReport) error {
	args := windowArgs(outletID, from, to)
	if err := s.DB.QueryRowContext(ctx, `SELECT COALESCE(SUM(o.grand_total_paise),0), COUNT(*) FROM orders o WHERE `+paidWindow,
		args...).Scan(&rep.SalesPaise, &rep.OrderCount); err != nil {
		return err
	}
	if rep.OrderCount > 0 {
		rep.AOVPaise = rep.SalesPaise / int64(rep.OrderCount)
	}
	if err := s.DB.QueryRowContext(ctx, `SELECT COALESCE(SUM(amount_paise),0) FROM refunds WHERE outlet_id = ? AND ts >= ? AND ts < ?`,
		args...).Scan(&rep.RefundsPaise); err != nil {
		return err
	}
	rep.NetSalesPaise = rep.SalesPaise - rep.RefundsPaise

	if err := s.sumInto(ctx, rep.SalesByType, `SELECT o.type, SUM(o.grand_total_paise) FROM orders o WHERE `+paidWindow+` GROUP BY o.type`, args...); err != nil {
		return err
	}
	// Tender split from the per-leg ledger; pre-016 orders (no legs) fall
	// back to their single payment_method.
	tenderArgs := append(append([]any{}, args...), args...)
	if err := s.sumInto(ctx, rep.SalesByTender, `
		SELECT op.method, SUM(op.amount_paise) FROM order_payments op JOIN orders o ON o.id = op.order_id
		WHERE `+paidWindow+` GROUP BY op.method
		UNION ALL
		SELECT COALESCE(o.payment_method, 'unknown'), SUM(o.grand_total_paise) FROM orders o
		WHERE `+paidWindow+` AND NOT EXISTS (SELECT 1 FROM order_payments op WHERE op.order_id = o.id)
		GROUP BY COALESCE(o.payment_method, 'unknown')`, tenderArgs...); err != nil {
		return err
	}

	rows, err := s.DB.QueryContext(ctx, `SELECT COALESCE(oi.name, mi.name, '?') AS n, SUM(oi.quantity), SUM(oi.total_paise)
		FROM order_items oi JOIN orders o ON o.id = oi.order_id LEFT JOIN menu_items mi ON mi.id = oi.menu_item_id
		WHERE `+paidWindow+` AND oi.is_cancelled = 0
		GROUP BY n ORDER BY SUM(oi.total_paise) DESC, n LIMIT 10`, args...)
	if err != nil {
		return err
	}
	for rows.Next() {
		var it models.ItemSales
		if err := rows.Scan(&it.Name, &it.Quantity, &it.Revenue); err != nil {
			rows.Close()
			return err
		}
		rep.TopItems = append(rep.TopItems, it)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}

	rows, err = s.DB.QueryContext(ctx, `SELECT COALESCE(mc.name, 'Uncategorized') AS c, SUM(oi.quantity), SUM(oi.total_paise)
		FROM order_items oi JOIN orders o ON o.id = oi.order_id
		LEFT JOIN menu_items mi ON mi.id = oi.menu_item_id LEFT JOIN menu_categories mc ON mc.id = mi.category_id
		WHERE `+paidWindow+` AND oi.is_cancelled = 0
		GROUP BY c ORDER BY SUM(oi.total_paise) DESC, c LIMIT 5`, args...)
	if err != nil {
		return err
	}
	for rows.Next() {
		var c models.CategorySales
		if err := rows.Scan(&c.Category, &c.Quantity, &c.Revenue); err != nil {
			rows.Close()
			return err
		}
		rep.TopCategories = append(rep.TopCategories, c)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}

	rows, err = s.DB.QueryContext(ctx, `SELECT COALESCE(o.waiter_id, ''), COALESCE(MAX(o.waiter_name), ''), COUNT(*), SUM(o.grand_total_paise)
		FROM orders o WHERE `+paidWindow+` GROUP BY COALESCE(o.waiter_id, '') ORDER BY SUM(o.grand_total_paise) DESC`, args...)
	if err != nil {
		return err
	}
	for rows.Next() {
		var st models.StaffSales
		if err := rows.Scan(&st.StaffID, &st.StaffName, &st.OrderCount, &st.Revenue); err != nil {
			rows.Close()
			return err
		}
		rep.StaffSales = append(rep.StaffSales, st)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}

	if rep.ExpensesPaise, err = s.SumExpensesBetween(ctx, outletID, from, to); err != nil {
		return err
	}
	if rep.ExpensesByCategory, err = s.ExpensesByCategory(ctx, outletID, from, to); err != nil {
		return err
	}
	return s.DB.QueryRowContext(ctx, `SELECT COUNT(*) FROM kots WHERE outlet_id = ? AND status NOT IN ('served','cancelled')`,
		outletID).Scan(&rep.PendingKOTs)
}

func (s *Store) sumInto(ctx context.Context, dst map[string]int64, q string, args ...any) error {
	rows, err := s.DB.QueryContext(ctx, q, args...)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var k string
		var v int64
		if err := rows.Scan(&k, &v); err != nil {
			return err
		}
		dst[k] += v
	}
	return rows.Err()
}
