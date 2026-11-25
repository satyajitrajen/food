package store

// Historical sales from another billing app's "Order Report" (see
// internal/orderimport), recorded as completed, paid orders so they count in
// daily and monthly reports. Imported orders are marked: order number
// "IMP-<invoice>", invoice "EXT-<invoice>", idempotency key
// "import:<outlet>:<invoice>" (a re-run never imports the same invoice twice)
// and an order note naming the source.

import (
	"context"
	"database/sql"
	"fmt"
	"math"
	"strings"
	"time"

	"foodpos/backend/internal/orderimport"
)

// ImportOrdersOptions tunes an import run.
type ImportOrdersOptions struct {
	Apply             bool              // false = plan only, nothing written
	OrderType         string            // dine_in | takeaway | delivery
	Source            string            // shown in the order note, e.g. the file name
	Aliases           map[string]string // report item name → "Item" or "Item / Variant"
	IncludeDuplicates bool              // import even when a same-day, same-total Hishobkr sale exists
	Loc               *time.Location    // the outlet's local time zone
}

// ImportOrderResult is the outcome for one report order.
type ImportOrderResult struct {
	Invoice    string
	Date       string
	TotalPaise int64
	Status     string // imported | would import | already imported | likely duplicate
	Detail     string
}

// ImportOrdersReport summarises a run. Unmatched lists report item names that
// match no menu item; any unmatched name stops the whole run.
type ImportOrdersReport struct {
	Results   []ImportOrderResult
	Unmatched []string
}

type menuMatch struct {
	itemID, itemName, variantID, variantName string
	isVeg                                    bool
}

func normName(s string) string { return strings.Join(strings.Fields(strings.ToLower(s)), " ") }

// PaymentMethodFor maps a report's payment type to a Hishobkr method.
func PaymentMethodFor(s string) (string, bool) {
	switch v := normName(s); {
	case v == "cash":
		return "cash", true
	case v == "upi" || strings.Contains(v, "gpay") || strings.Contains(v, "google pay") || strings.Contains(v, "phonepe") ||
		strings.Contains(v, "paytm") || v == "online" || v == "bank" || strings.Contains(v, "upi"):
		return "upi", true
	case strings.Contains(v, "card"):
		return "card", true
	}
	return "", false
}

// loadMenuIndex returns every way a report line can name a menu item or option:
// "Item", "Variant Item", "Item Variant", "Item (Variant)".
func (s *Store) loadMenuIndex(ctx context.Context, outletID string) (map[string]menuMatch, error) {
	idx := map[string]menuMatch{}
	rows, err := s.DB.QueryContext(ctx, `SELECT m.id, m.name, m.is_veg, COALESCE(v.id, ''), COALESCE(v.name, '')
		FROM menu_items m LEFT JOIN product_variants v ON v.menu_item_id = m.id
		WHERE m.outlet_id = ? AND m.is_deleted = 0 ORDER BY m.id, v.seq`, outletID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	hasVariants := map[string]bool{}
	for rows.Next() {
		var mm menuMatch
		var veg int
		if err := rows.Scan(&mm.itemID, &mm.itemName, &veg, &mm.variantID, &mm.variantName); err != nil {
			return nil, err
		}
		mm.isVeg = veg == 1
		if mm.variantID == "" {
			idx[normName(mm.itemName)] = mm
			continue
		}
		hasVariants[mm.itemID] = true
		for _, k := range []string{mm.variantName + " " + mm.itemName, mm.itemName + " " + mm.variantName,
			mm.itemName + " (" + mm.variantName + ")", mm.itemName + " / " + mm.variantName} {
			idx[normName(k)] = mm
		}
	}
	return idx, rows.Err()
}

// ImportOrders records report orders into outletID. With opts.Apply false it
// only reports what would happen.
func (s *Store) ImportOrders(ctx context.Context, outletID string, orders []orderimport.Order, opts ImportOrdersOptions) (ImportOrdersReport, error) {
	var rep ImportOrdersReport
	if _, err := s.GetOutlet(ctx, outletID); err != nil {
		return rep, fmt.Errorf("outlet %s: %w", outletID, err)
	}
	if opts.Loc == nil {
		opts.Loc = time.UTC
	}
	switch opts.OrderType {
	case "dine_in", "takeaway", "delivery":
	default:
		return rep, fmt.Errorf("order type %q must be dine_in, takeaway or delivery", opts.OrderType)
	}
	idx, err := s.loadMenuIndex(ctx, outletID)
	if err != nil {
		return rep, err
	}

	// Resolve every line first: one unknown item stops the run before anything is written.
	resolve := func(name string) (menuMatch, bool) {
		if alias, ok := opts.Aliases[normName(name)]; ok {
			name = alias
		}
		m, ok := idx[normName(name)]
		return m, ok
	}
	seen := map[string]bool{}
	for _, o := range orders {
		if _, ok := PaymentMethodFor(o.PaymentType); !ok {
			return rep, fmt.Errorf("order %s: unknown payment type %q (expected cash, UPI or card)", o.Invoice, o.PaymentType)
		}
		for _, l := range o.Lines {
			if _, ok := resolve(l.Name); !ok && !seen[normName(l.Name)] {
				seen[normName(l.Name)] = true
				rep.Unmatched = append(rep.Unmatched, l.Name)
			}
		}
	}
	if len(rep.Unmatched) > 0 {
		return rep, fmt.Errorf("%d report item name(s) match nothing on the menu; add them with -map", len(rep.Unmatched))
	}

	err = s.withTx(ctx, func(tx *sql.Tx) error {
		for _, o := range orders {
			res := ImportOrderResult{Invoice: o.Invoice, Date: o.Date.Format("02 Jan 2006"), TotalPaise: o.TotalPaise}
			key := "import:" + outletID + ":" + o.Invoice

			var n int
			if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM orders WHERE idempotency_key = ?`, key).Scan(&n); err != nil {
				return err
			}
			if n > 0 {
				res.Status = "already imported"
				rep.Results = append(rep.Results, res)
				continue
			}

			// Same day (outlet time), same total, already rung up in Hishobkr itself?
			dayStart := time.Date(o.Date.Year(), o.Date.Month(), o.Date.Day(), 0, 0, 0, 0, opts.Loc)
			if !opts.IncludeDuplicates {
				var dup string
				err := tx.QueryRowContext(ctx, `SELECT order_number FROM orders
					WHERE outlet_id = ? AND status IN ('completed','refunded') AND paid_at >= ? AND paid_at < ?
					  AND grand_total_paise = ? AND (idempotency_key IS NULL OR idempotency_key NOT LIKE 'import:%')
					LIMIT 1`, outletID, TimeStr(dayStart), TimeStr(dayStart.AddDate(0, 0, 1)), o.TotalPaise).Scan(&dup)
				if err == nil {
					res.Status = "likely duplicate"
					res.Detail = "same day and total as " + dup + " already in Hishobkr"
					rep.Results = append(rep.Results, res)
					continue
				} else if err != sql.ErrNoRows {
					return err
				}
			}

			var subtotal, discount, tax int64
			for _, l := range o.Lines {
				subtotal += l.UnitPaise * int64(l.Quantity)
				discount += l.DiscountPaise
				tax += l.CGSTPaise + l.SGSTPaise
			}
			taxPct := 0.0
			if base := subtotal - discount; base > 0 && tax > 0 {
				taxPct = math.Round(float64(tax)/float64(base)*10000) / 100
			}
			method, _ := PaymentMethodFor(o.PaymentType)
			paidAt := TimeStr(dayStart.Add(12 * time.Hour)) // reports carry no time of day
			customer := o.Customer
			if normName(customer) == "cash sale" {
				customer = ""
			}
			res.Status = "would import"
			if opts.Apply {
				orderID := NewID("ord")
				note := fmt.Sprintf("Imported from %s, invoice %s", opts.Source, o.Invoice)
				if _, err := tx.ExecContext(ctx, `INSERT INTO orders (id, outlet_id, order_number, type, status, customer_name,
					customer_phone, order_note, subtotal_paise, discount_paise, tax_percent, tax_paise, service_paise,
					grand_total_paise, invoice_number, paid_at, payment_method, paid_paise, idempotency_key, created_at, updated_at)
					VALUES (?, ?, ?, ?, 'completed', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
					orderID, outletID, "IMP-"+o.Invoice, opts.OrderType, nullIfBlank(customer), nullIfBlank(o.Phone), note,
					subtotal, discount, taxPct, tax, o.ServicePaise, o.TotalPaise, "EXT-"+o.Invoice, paidAt, method,
					o.TotalPaise, key, paidAt, TimeStr(Now())); err != nil {
					return fmt.Errorf("order %s: %w", o.Invoice, err)
				}
				for _, l := range o.Lines {
					m, _ := resolve(l.Name)
					veg := 0
					if m.isVeg {
						veg = 1
					}
					if _, err := tx.ExecContext(ctx, `INSERT INTO order_items (id, order_id, menu_item_id, variant_id, quantity,
						unit_paise, total_paise, is_kot_sent, name, variant_name, is_veg) VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?)`,
						NewID("oi"), orderID, m.itemID, nullIfBlank(m.variantID), l.Quantity, l.UnitPaise,
						l.UnitPaise*int64(l.Quantity), m.itemName, nullIfBlank(m.variantName), veg); err != nil {
						return fmt.Errorf("order %s item %q: %w", o.Invoice, l.Name, err)
					}
				}
				if _, err := tx.ExecContext(ctx, `INSERT INTO order_payments (id, order_id, method, amount_paise) VALUES (?, ?, ?, ?)`,
					NewID("pay"), orderID, method, o.TotalPaise); err != nil {
					return fmt.Errorf("order %s payment: %w", o.Invoice, err)
				}
				res.Status = "imported"
			}
			rep.Results = append(rep.Results, res)
		}
		if !opts.Apply {
			return errDryRun
		}
		return nil
	})
	if err == errDryRun {
		err = nil
	}
	return rep, err
}

var errDryRun = fmt.Errorf("dry run")

func nullIfBlank(s string) any {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	return s
}
