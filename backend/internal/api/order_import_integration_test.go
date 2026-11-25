package api_test

// cmd/admin import-orders' store path against a fresh outlet: report orders
// become completed, paid orders; a re-run imports nothing twice; a sale that was
// already rung up in Hishobkr is held back as a likely duplicate; an unknown
// item name stops the run before anything is written.

import (
	"context"
	"strings"
	"testing"
	"time"

	"foodpos/backend/internal/orderimport"
	"foodpos/backend/internal/store"
)

func TestOrderImport(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	exec := func(q string, args ...any) {
		t.Helper()
		if _, err := e.st.DB.Exec(q, args...); err != nil {
			t.Fatal(err)
		}
	}
	// Fresh outlet per run (the test database is shared across runs).
	out := store.NewID("out")
	exec(`INSERT INTO outlets (id, org_id, name, terminal) VALUES (?, 'org-01', 'Order Import', 'POS-8')`, out)
	cat := store.NewID("cat")
	exec(`INSERT INTO menu_categories (id, outlet_id, name) VALUES (?, ?, 'Snacks')`, cat, out)
	sandwich, roll := store.NewID("m"), store.NewID("m")
	exec(`INSERT INTO menu_items (id, outlet_id, category_id, name, price_paise) VALUES (?, ?, ?, 'Veg Sandwich', 10000)`, sandwich, out, cat)
	exec(`INSERT INTO menu_items (id, outlet_id, category_id, name, price_paise, is_veg) VALUES (?, ?, ?, 'Kathi Roll', 6000, 0)`, roll, out, cat)
	vegRoll := store.NewID("v")
	exec(`INSERT INTO product_variants (id, menu_item_id, name, price_paise) VALUES (?, ?, 'Veg', 6000)`, vegRoll, roll)
	exec(`INSERT INTO product_variants (id, menu_item_id, name, price_paise) VALUES (?, ?, 'Single Egg', 8000)`, store.NewID("v"), roll)

	loc := time.FixedZone("IST", 5*3600+1800)
	day := time.Date(2026, 11, 20, 0, 0, 0, 0, loc)
	orders := []orderimport.Order{
		{Invoice: "3001", Date: day, Customer: "Cash Sale", PaymentType: "Cash", TotalPaise: 64000, Lines: []orderimport.Line{
			{Name: "Veg Sandwich", Quantity: 4, UnitPaise: 10000, AmountPaise: 40000},
			{Name: "veg  kathi roll", Quantity: 4, UnitPaise: 6000, AmountPaise: 24000},
		}},
		{Invoice: "3002", Date: day.AddDate(0, 0, 1), Customer: "Ravi", Phone: "9876543210", PaymentType: "GPay", TotalPaise: 16000, Lines: []orderimport.Line{
			{Name: "Egg Kathi Roll", Quantity: 2, UnitPaise: 8000, AmountPaise: 16000},
		}},
	}
	opts := store.ImportOrdersOptions{OrderType: "takeaway", Source: "test.xlsx", Loc: loc}

	// "Egg Kathi Roll" matches nothing until mapped; nothing is written.
	rep, err := e.st.ImportOrders(ctx, out, orders, opts)
	if err == nil || len(rep.Unmatched) != 1 || rep.Unmatched[0] != "Egg Kathi Roll" {
		t.Fatalf("want 1 unmatched (Egg Kathi Roll), got %v / %v", rep.Unmatched, err)
	}
	opts.Aliases = map[string]string{"egg kathi roll": "Kathi Roll / Single Egg"}

	// Dry run writes nothing.
	if rep, err = e.st.ImportOrders(ctx, out, orders, opts); err != nil || rep.Results[0].Status != "would import" {
		t.Fatalf("dry run = %+v, %v", rep.Results, err)
	}
	var n int
	_ = e.st.DB.QueryRow(`SELECT COUNT(*) FROM orders WHERE outlet_id = ?`, out).Scan(&n)
	if n != 0 {
		t.Fatalf("dry run wrote %d orders", n)
	}

	opts.Apply = true
	if rep, err = e.st.ImportOrders(ctx, out, orders, opts); err != nil {
		t.Fatal(err)
	}
	for _, r := range rep.Results {
		if r.Status != "imported" {
			t.Fatalf("apply = %+v", rep.Results)
		}
	}
	var status, method, paidAt, invoice string
	var total int64
	if err := e.st.DB.QueryRow(`SELECT status, payment_method, paid_at, invoice_number, grand_total_paise FROM orders
		WHERE outlet_id = ? AND order_number = 'IMP-3002'`, out).Scan(&status, &method, &paidAt, &invoice, &total); err != nil {
		t.Fatal(err)
	}
	if status != "completed" || method != "upi" || invoice != "EXT-3002" || total != 16000 ||
		!strings.HasPrefix(paidAt, "2026-11-21T06:30:00") {
		t.Fatalf("imported order = %s %s %s %s %d", status, method, paidAt, invoice, total)
	}
	var variant string
	_ = e.st.DB.QueryRow(`SELECT COALESCE(oi.variant_name, '') FROM order_items oi JOIN orders o ON o.id = oi.order_id
		WHERE o.outlet_id = ? AND o.order_number = 'IMP-3002'`, out).Scan(&variant)
	if variant != "Single Egg" {
		t.Fatalf("mapped variant = %q", variant)
	}

	// Re-run: nothing imported twice.
	if rep, err = e.st.ImportOrders(ctx, out, orders, opts); err != nil || rep.Results[0].Status != "already imported" {
		t.Fatalf("re-run = %+v, %v", rep.Results, err)
	}

	// A sale already rung up in Hishobkr on that day for that total is held back.
	exec(`INSERT INTO orders (id, outlet_id, order_number, type, status, grand_total_paise, paid_at, created_at, updated_at)
		VALUES (?, ?, 'ORD-1', 'dine_in', 'completed', 30000, ?, ?, ?)`, store.NewID("ord"), out,
		store.TimeStr(day.AddDate(0, 0, 2).Add(15*time.Hour)), store.TimeStr(day), store.TimeStr(day))
	dup := []orderimport.Order{{Invoice: "3003", Date: day.AddDate(0, 0, 2), PaymentType: "Cash", TotalPaise: 30000,
		Lines: []orderimport.Line{{Name: "Veg Sandwich", Quantity: 3, UnitPaise: 10000, AmountPaise: 30000}}}}
	if rep, err = e.st.ImportOrders(ctx, out, dup, opts); err != nil || rep.Results[0].Status != "likely duplicate" {
		t.Fatalf("duplicate = %+v, %v", rep.Results, err)
	}
}
