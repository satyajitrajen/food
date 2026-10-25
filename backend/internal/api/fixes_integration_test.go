package api_test

// Integration coverage for the backend review fixes: dead features revived,
// tenant/role security, money integrity (pay/refund/credit/split legs),
// closed-order immutability, snapshots, reports and lockout. Every test
// builds its own outlet (fixture) so tests never share tables or shifts.

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

var fxSeq int64

type fx struct {
	e       *env
	outlet  string
	table   string
	item    string // ₹100, veg, available
	waiterA string
	waiterB string
}

const fxPIN = "4444"

func newFixture(t *testing.T) *fx {
	t.Helper()
	e := newEnv(t)
	n := atomic.AddInt64(&fxSeq, 1)
	id := fmt.Sprintf("out-fx%d-%d", time.Now().UnixNano()%1e9, n)
	f := &fx{e: e, outlet: id, table: "t-" + id, item: "m-" + id, waiterA: "wa-" + id, waiterB: "wb-" + id}
	hash, _ := e.mgr.HashPIN(fxPIN)
	for _, q := range []struct {
		sql  string
		args []any
	}{
		{`INSERT INTO outlets (id, org_id, name, terminal, timezone) VALUES (?, 'org-01', 'Fixture', 'POS-F', 'Asia/Kolkata')`, []any{id}},
		{`INSERT INTO settings (outlet_id, restaurant_name, gst_percent, service_percent, packaging_paise, delivery_paise)
			VALUES (?, 'Fixture', 0, 0, 0, 0)`, []any{id}},
		{`INSERT INTO tables (id, outlet_id, table_number, seats, floor, status) VALUES (?, ?, 'F1', 4, 'Main', 'available')`, []any{f.table, id}},
		{`INSERT INTO menu_categories (id, outlet_id, name) VALUES (?, ?, 'Mains')`, []any{"cat-" + id, id}},
		{`INSERT INTO menu_items (id, outlet_id, category_id, name, price_paise, is_veg, is_available)
			VALUES (?, ?, ?, 'Dal Fry', 10000, 1, 1)`, []any{f.item, id, "cat-" + id}},
		{`INSERT INTO staff (id, org_id, outlet_id, name, role, pin_hash, is_active) VALUES (?, 'org-01', ?, 'Waiter A', 'waiter', ?, 1)`, []any{f.waiterA, id, hash}},
		{`INSERT INTO staff (id, org_id, outlet_id, name, role, pin_hash, is_active) VALUES (?, 'org-01', ?, 'Waiter B', 'waiter', ?, 1)`, []any{f.waiterB, id, hash}},
	} {
		if _, err := e.st.DB.Exec(q.sql, q.args...); err != nil {
			t.Fatalf("fixture: %v", err)
		}
	}
	// Fixture waiters live in the shared demo org: drop them afterwards so
	// they never count against its plan's staff limit.
	t.Cleanup(func() {
		_, _ = e.st.DB.Exec(`DELETE FROM staff WHERE id IN (?, ?)`, f.waiterA, f.waiterB)
	})
	return f
}

func (f *fx) login(t *testing.T, staffID, pin string) string {
	t.Helper()
	code, body := f.e.do(t, "POST", "/api/v1/auth/login", map[string]string{
		"staff_id": staffID, "pin": pin, "outlet_id": f.outlet,
	}, false)
	if code != 200 {
		t.Fatalf("login %s: %d %v", staffID, code, body)
	}
	return body["token"].(string)
}

func (f *fx) cashier(t *testing.T) string { return f.login(t, "st-01", "1234") }
func (f *fx) manager(t *testing.T) string { return f.login(t, "st-02", "9999") }
func (f *fx) admin(t *testing.T) string   { return f.login(t, "st-03", "0000") }

// call performs a request as token (goroutine-safe: no t.Fatal inside).
func (f *fx) call(token, method, path string, body any, idemKey string) (int, map[string]any) {
	var buf bytes.Buffer
	if body != nil {
		_ = json.NewEncoder(&buf).Encode(body)
	}
	req, _ := http.NewRequest(method, f.e.ts.URL+path, &buf)
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	if idemKey != "" {
		req.Header.Set("Idempotency-Key", idemKey)
	}
	res, err := f.e.client.Do(req)
	if err != nil {
		return 0, map[string]any{"transport_error": err.Error()}
	}
	defer res.Body.Close()
	var out map[string]any
	_ = json.NewDecoder(res.Body).Decode(&out)
	return res.StatusCode, out
}

func (f *fx) must(t *testing.T, want int, token, method, path string, body any) map[string]any {
	t.Helper()
	code, out := f.call(token, method, path, body, "")
	if code != want {
		t.Fatalf("%s %s: got %d want %d: %v", method, path, code, want, out)
	}
	return out
}

func errCode(body map[string]any) string {
	if e, ok := body["error"].(map[string]any); ok {
		s, _ := e["code"].(string)
		return s
	}
	return ""
}

func num(v any) int64 { f, _ := v.(float64); return int64(f) }

// orderWithItem creates a takeaway order with qty × ₹100 and returns its id.
func (f *fx) orderWithItem(t *testing.T, token string, qty int) string {
	t.Helper()
	o := f.must(t, 201, token, "POST", "/api/v1/orders", map[string]any{"type": "takeaway"})
	id := o["id"].(string)
	f.must(t, 201, token, "POST", "/api/v1/orders/"+id+"/items", map[string]any{"menu_item_id": f.item, "quantity": qty})
	return id
}

func (f *fx) openShift(t *testing.T, token string) string {
	t.Helper()
	sh := f.must(t, 201, token, "POST", "/api/v1/shifts/open", map[string]any{"opening_paise": 100000})
	return sh["id"].(string)
}

func (f *fx) shift(t *testing.T, token string) map[string]any {
	t.Helper()
	body := f.must(t, 200, token, "GET", "/api/v1/shifts/current", nil)
	sh, _ := body["shift"].(map[string]any)
	if sh == nil {
		t.Fatal("no current shift")
	}
	return sh
}

// ---- dead features ----

func TestSupplierPaymentFlow(t *testing.T) {
	f := newFixture(t)
	mgr := f.manager(t)
	sup := f.must(t, 201, mgr, "POST", "/api/v1/suppliers", map[string]any{"name": "Dairy", "mobile": "9800000000"})
	supID := sup["id"].(string)
	f.must(t, 201, mgr, "POST", "/api/v1/purchases", map[string]any{
		"invoice_no": "P-1", "supplier_id": supID, "status": "pending", "total_paise": 90000,
	})
	pay := f.must(t, 201, mgr, "POST", "/api/v1/suppliers/"+supID+"/payments", map[string]any{"amount_paise": 50000, "method": "upi", "reference": "UTR1"})
	if got := num(pay["supplier"].(map[string]any)["outstanding_paise"]); got != 40000 {
		t.Fatalf("outstanding after payment = %d, want 40000", got)
	}
	code, body := f.call(mgr, "POST", "/api/v1/suppliers/"+supID+"/payments", map[string]any{"amount_paise": 50000, "method": "cash"}, "")
	if code != 400 || errCode(body) != "exceeds_due" {
		t.Fatalf("overpay: %d %v", code, body)
	}
	list := f.must(t, 200, mgr, "GET", "/api/v1/suppliers/"+supID+"/payments", nil)
	if n := len(list["payments"].([]any)); n != 1 {
		t.Fatalf("payments = %d, want 1", n)
	}
}

func TestListShiftsReturnsRows(t *testing.T) {
	f := newFixture(t)
	c := f.cashier(t)
	id := f.openShift(t, c)
	body := f.must(t, 200, c, "GET", "/api/v1/shifts", nil)
	rows := body["shifts"].([]any)
	if len(rows) != 1 || rows[0].(map[string]any)["id"] != id {
		t.Fatalf("shifts = %v", rows)
	}
}

func TestAttendanceClockIn(t *testing.T) {
	f := newFixture(t)
	tok := f.login(t, f.waiterA, fxPIN) // login auto clocks in
	first := f.must(t, 200, tok, "POST", "/api/v1/attendance/clock-in", nil)
	again := f.must(t, 200, tok, "POST", "/api/v1/attendance/clock-in", nil)
	idOf := func(m map[string]any) any {
		if a, ok := m["attendance"].(map[string]any); ok {
			return a["id"]
		}
		return m["id"]
	}
	if idOf(first) == nil || idOf(first) != idOf(again) {
		t.Fatalf("clock-in must reuse the open session: %v vs %v", first, again)
	}
	list := f.must(t, 200, tok, "GET", "/api/v1/attendance", nil)
	if n := len(list["attendance"].([]any)); n != 1 {
		t.Fatalf("attendance rows = %d, want 1", n)
	}
}

func TestWaiterSeesOnlyOwnOrders(t *testing.T) {
	f := newFixture(t)
	a := f.login(t, f.waiterA, fxPIN)
	b := f.login(t, f.waiterB, fxPIN)
	f.must(t, 201, a, "POST", "/api/v1/orders", map[string]any{"type": "takeaway"})
	f.must(t, 201, b, "POST", "/api/v1/orders", map[string]any{"type": "takeaway"})
	// A waiter cannot book an order under someone else.
	o := f.must(t, 201, a, "POST", "/api/v1/orders", map[string]any{"type": "takeaway", "waiter_id": f.waiterB})
	if o["waiter_id"] != f.waiterA {
		t.Fatalf("waiter order booked under %v", o["waiter_id"])
	}
	body := f.must(t, 200, a, "GET", "/api/v1/orders?waiter_id="+f.waiterB, nil)
	orders := body["orders"].([]any)
	if len(orders) != 2 {
		t.Fatalf("waiter A sees %d orders, want own 2", len(orders))
	}
	for _, raw := range orders {
		if raw.(map[string]any)["waiter_id"] != f.waiterA {
			t.Fatalf("waiter A sees a foreign order: %v", raw)
		}
	}
}

// ---- tenant & role security ----

func TestCrossOrgIsolation(t *testing.T) {
	f := newFixture(t)
	mgr := f.manager(t)
	// A second tenant.
	other := f.e.register(t, fmt.Sprintf("iso-%d@test", time.Now().UnixNano()))

	// Settings PUT ignores a foreign outlet_id and writes the caller's own.
	body := f.must(t, 200, mgr, "PUT", "/api/v1/settings", map[string]any{
		"outlet_id": other.Outlet, "restaurant_name": "Hijack", "gst_percent": 5,
	})
	if body["outlet_id"] != f.outlet {
		t.Fatalf("settings saved for %v, want own %s", body["outlet_id"], f.outlet)
	}
	var name string
	_ = f.e.st.DB.QueryRow(`SELECT restaurant_name FROM settings WHERE outlet_id = ?`, other.Outlet).Scan(&name)
	if name == "Hijack" {
		t.Fatal("foreign outlet settings were overwritten")
	}

	// A foreign table cannot be used for an order.
	var foreignTable string
	_ = f.e.st.DB.QueryRow(`INSERT INTO tables (id, outlet_id, table_number, seats, floor, status)
		VALUES (?, ?, 'X1', 2, 'Main', 'available') RETURNING id`, "t-foreign-"+other.Outlet, other.Outlet).Scan(&foreignTable)
	code, resp := f.call(mgr, "POST", "/api/v1/orders", map[string]any{"type": "dine_in", "table_id": foreignTable}, "")
	if code != 400 || errCode(resp) != "invalid_table" {
		t.Fatalf("foreign table order: %d %v", code, resp)
	}
	// An occupied table answers 409 without naming the other order.
	first := f.must(t, 201, mgr, "POST", "/api/v1/orders", map[string]any{"type": "dine_in", "table_id": f.table})
	code, resp = f.call(mgr, "POST", "/api/v1/orders", map[string]any{"type": "dine_in", "table_id": f.table}, "")
	raw, _ := json.Marshal(resp)
	if code != 409 || strings.Contains(string(raw), first["id"].(string)) {
		t.Fatalf("occupied table: %d %s", code, raw)
	}
	// A foreign outlet is invisible.
	if code, _ := f.call(mgr, "GET", "/api/v1/outlets/"+other.Outlet, nil, ""); code != 404 {
		t.Fatalf("foreign outlet GET = %d, want 404", code)
	}
}

func TestManagerCannotEscalateToAdmin(t *testing.T) {
	f := newFixture(t)
	mgr := f.manager(t)
	if code, body := f.call(mgr, "PATCH", "/api/v1/staff/"+f.waiterA, map[string]any{"role": "admin"}, ""); code != 403 {
		t.Fatalf("manager promoting to admin: %d %v", code, body)
	}
	if code, body := f.call(mgr, "PATCH", "/api/v1/staff/st-03", map[string]any{"name": "Owned"}, ""); code != 403 {
		t.Fatalf("manager editing admin: %d %v", code, body)
	}
	if code, body := f.call(mgr, "POST", "/api/v1/staff", map[string]any{"name": "X", "role": "admin", "pin": "1234"}, ""); code != 403 {
		t.Fatalf("manager creating admin: %d %v", code, body)
	}
	// An admin may.
	adm := f.admin(t)
	f.must(t, 200, adm, "PATCH", "/api/v1/staff/"+f.waiterB, map[string]any{"role": "cashier"})
}

func TestRoleGates(t *testing.T) {
	f := newFixture(t)
	w := f.login(t, f.waiterA, fxPIN)
	c := f.cashier(t)
	for _, tc := range []struct {
		token, method, path string
		body                any
	}{
		{w, "POST", "/api/v1/shifts/open", map[string]any{"opening_paise": 0}},
		{w, "POST", "/api/v1/expenses", map[string]any{"title": "x", "category": "c", "amount_paise": 100, "method": "cash"}},
		{w, "POST", "/api/v1/shifts/current/cash-move", map[string]any{"type": "cash_in", "amount_paise": 100}},
		{c, "POST", "/api/v1/tables", map[string]any{"table_number": "Z9", "seats": 2}},
		{c, "POST", "/api/v1/inventory/x/adjust", map[string]any{"delta": 1, "reason": "r"}},
		{c, "PATCH", "/api/v1/outlets/" + f.outlet, map[string]any{"name": "N"}},
		{c, "DELETE", "/api/v1/expenses/x", nil},
	} {
		if code, body := f.call(tc.token, tc.method, tc.path, tc.body, ""); code != 403 {
			t.Errorf("%s %s: got %d want 403 (%v)", tc.method, tc.path, code, body)
		}
	}
	// Waiters cannot settle bills.
	id := f.orderWithItem(t, w, 1)
	if code, _ := f.call(w, "POST", "/api/v1/orders/"+id+"/pay", map[string]any{"method": "upi"}, ""); code != 403 {
		t.Fatalf("waiter pay = %d, want 403", code)
	}
}

func TestSSEStreamRequiresStaffTicket(t *testing.T) {
	f := newFixture(t)
	c := f.cashier(t)
	// A raw JWT in the URL is no longer accepted.
	res, err := f.e.client.Get(f.e.ts.URL + "/api/v1/ws?token=" + c)
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	if res.StatusCode != 401 {
		t.Fatalf("legacy ?token= stream = %d, want 401", res.StatusCode)
	}
	// Owner tokens cannot mint a stream ticket.
	f.e.register(t, fmt.Sprintf("sse-%d@test", time.Now().UnixNano()))
	if code, body := f.call(f.e.token, "POST", "/api/v1/ws/ticket", nil, ""); code != 403 {
		t.Fatalf("owner ticket = %d %v, want 403", code, body)
	}
}

func TestPINLockout(t *testing.T) {
	f := newFixture(t)
	for i := 1; i <= 5; i++ {
		code, body := f.call("", "POST", "/api/v1/auth/login", map[string]string{"staff_id": f.waiterA, "pin": "0001", "outlet_id": f.outlet}, "")
		want := 401
		if i == 5 {
			want = 429
		}
		if code != want {
			t.Fatalf("attempt %d: got %d want %d (%v)", i, code, want, body)
		}
	}
	code, body := f.call("", "POST", "/api/v1/auth/login", map[string]string{"staff_id": f.waiterA, "pin": fxPIN, "outlet_id": f.outlet}, "")
	if code != 429 || errCode(body) != "pin_locked" {
		t.Fatalf("correct PIN while locked: %d %v", code, body)
	}
	// Other staff are unaffected.
	f.login(t, f.waiterB, fxPIN)

	// Manager-PIN guesses lock the requesting actor too.
	c := f.cashier(t)
	for i := 1; i <= 5; i++ {
		code, body = f.call(c, "POST", "/api/v1/auth/verify-manager-pin", map[string]string{"pin": "0101"}, "")
		if i < 5 && (code != 200 || body["valid"] != false) {
			t.Fatalf("verify attempt %d: %d %v", i, code, body)
		}
	}
	if code != 429 {
		t.Fatalf("5th wrong manager PIN = %d, want 429", code)
	}
}

func TestOutletPatch(t *testing.T) {
	f := newFixture(t)
	mgr := f.manager(t)
	if code, body := f.call(mgr, "PATCH", "/api/v1/outlets/"+f.outlet, map[string]any{"timezone": "Mars/Base"}, ""); code != 400 {
		t.Fatalf("bad timezone: %d %v", code, body)
	}
	f.must(t, 200, mgr, "PATCH", "/api/v1/outlets/"+f.outlet, map[string]any{
		"name": " Green Candle ", "email": "gc@x.in", "gstin": "27ABCDE1234F1Z5", "timezone": "Asia/Dubai",
	})
	got := f.must(t, 200, mgr, "GET", "/api/v1/outlets/"+f.outlet, nil)
	if got["name"] != "Green Candle" || got["email"] != "gc@x.in" || got["timezone"] != "Asia/Dubai" {
		t.Fatalf("outlet after patch = %v", got)
	}
}

// ---- money integrity ----

func TestConcurrentPayOneWins(t *testing.T) {
	f := newFixture(t)
	c := f.cashier(t)
	f.openShift(t, c)
	id := f.orderWithItem(t, c, 2) // ₹200
	const n = 8
	var ok, conflict int64
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			code, body := f.call(c, "POST", "/api/v1/orders/"+id+"/pay", map[string]any{"method": "cash", "amount_received_paise": 20000}, "")
			switch {
			case code == 200:
				atomic.AddInt64(&ok, 1)
			case code == 409 && errCode(body) == "already_paid":
				atomic.AddInt64(&conflict, 1)
			}
		}()
	}
	wg.Wait()
	if ok != 1 || conflict != n-1 {
		t.Fatalf("pay race: %d ok, %d already_paid (want 1/%d)", ok, conflict, n-1)
	}
	if got := num(f.shift(t, c)["cash_sales_paise"]); got != 20000 {
		t.Fatalf("cash sales = %d, want 20000 booked once", got)
	}
}

func TestUniqueInvoicesUnderConcurrency(t *testing.T) {
	f := newFixture(t)
	c := f.cashier(t)
	f.openShift(t, c)
	const n = 10
	ids := make([]string, n)
	for i := range ids {
		ids[i] = f.orderWithItem(t, c, 1)
	}
	invoices := make([]string, n)
	var wg sync.WaitGroup
	for i := range ids {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			_, body := f.call(c, "POST", "/api/v1/orders/"+ids[i]+"/pay", map[string]any{"method": "upi"}, "")
			invoices[i], _ = body["invoice_number"].(string)
		}(i)
	}
	wg.Wait()
	seen := map[string]bool{}
	for _, inv := range invoices {
		if inv == "" || seen[inv] {
			t.Fatalf("invoice numbers not unique/complete: %v", invoices)
		}
		seen[inv] = true
	}
}

func TestRefundCaps(t *testing.T) {
	f := newFixture(t)
	c := f.cashier(t)
	f.openShift(t, c)
	id := f.orderWithItem(t, c, 1) // ₹100
	paid := f.must(t, 200, c, "POST", "/api/v1/orders/"+id+"/pay", map[string]any{"method": "cash", "amount_received_paise": 50000})
	if num(paid["change_paise"]) != 40000 {
		t.Fatalf("change = %v", paid["change_paise"])
	}
	refund := func(amount int64, full bool, key string) (int, map[string]any) {
		return f.call(c, "POST", "/api/v1/orders/"+id+"/refund", map[string]any{
			"amount_paise": amount, "reason": "test", "mode": "original", "is_full_refund": full, "manager_pin": "9999",
		}, key)
	}
	// The cap is the bill total, never the cash handed over (₹500).
	if code, body := refund(20000, false, ""); code != 400 || errCode(body) != "refund_exceeds_total" {
		t.Fatalf("refund above total: %d %v", code, body)
	}
	if code, body := refund(3000, false, "rf-1"); code != 200 || num(body["order"].(map[string]any)["refunded_paise"]) != 3000 {
		t.Fatalf("partial refund: %d %v", code, body)
	}
	// Replay with the same key is idempotent (no second refund).
	if code, body := refund(3000, false, "rf-1"); code != 200 || num(body["order"].(map[string]any)["refunded_paise"]) != 3000 {
		t.Fatalf("replayed refund: %d %v", code, body)
	}
	if code, body := refund(8000, false, ""); code != 400 {
		t.Fatalf("refund above remaining: %d %v", code, body)
	}
	code, body := refund(0, true, "")
	if code != 200 {
		t.Fatalf("full remaining refund: %d %v", code, body)
	}
	o := body["order"].(map[string]any)
	if o["status"] != "refunded" || num(o["refunded_paise"]) != 10000 {
		t.Fatalf("after full refund: %v", o)
	}
	if code, _ := refund(100, false, ""); code != 409 {
		t.Fatalf("refund of a refunded order = %d, want 409", code)
	}
	if got := num(f.shift(t, c)["refunds_cash_paise"]); got != 10000 {
		t.Fatalf("cash refunds booked = %d, want 10000", got)
	}
}

func TestSplitPaymentLegs(t *testing.T) {
	f := newFixture(t)
	c := f.cashier(t)
	f.openShift(t, c)
	id := f.orderWithItem(t, c, 3) // ₹300
	// ₹150 cash tendered (₹50 change) + ₹200 UPI.
	f.must(t, 200, c, "POST", "/api/v1/orders/"+id+"/pay", map[string]any{
		"method": "cash", "splits": []map[string]any{{"method": "cash", "amount_paise": 15000}, {"method": "upi", "amount_paise": 20000}},
	})
	sh := f.shift(t, c)
	if num(sh["cash_sales_paise"]) != 10000 || num(sh["upi_sales_paise"]) != 20000 {
		t.Fatalf("legs booked cash=%v upi=%v, want 10000/20000", sh["cash_sales_paise"], sh["upi_sales_paise"])
	}
	adm := f.admin(t)
	rep := f.must(t, 200, adm, "GET", "/api/v1/reports/dashboard", nil)
	tender := rep["sales_by_tender"].(map[string]any)
	if num(tender["cash"]) != 10000 || num(tender["upi"]) != 20000 {
		t.Fatalf("sales_by_tender = %v", tender)
	}
}

func TestClosedOrderIsImmutable(t *testing.T) {
	f := newFixture(t)
	c := f.cashier(t)
	f.openShift(t, c)
	id := f.orderWithItem(t, c, 1)
	f.must(t, 200, c, "POST", "/api/v1/orders/"+id+"/pay", map[string]any{"method": "card"})
	for _, tc := range []struct {
		method, path string
		body         any
	}{
		{"POST", "/api/v1/orders/" + id + "/items", map[string]any{"menu_item_id": f.item, "quantity": 1}},
		{"PATCH", "/api/v1/orders/" + id, map[string]any{"order_note": "late"}},
		{"POST", "/api/v1/orders/" + id + "/kot", map[string]any{}},
		{"POST", "/api/v1/orders/" + id + "/pay", map[string]any{"method": "upi"}},
	} {
		if code, body := f.call(c, tc.method, tc.path, tc.body, ""); code != 409 {
			t.Errorf("%s %s on a paid order: %d %v", tc.method, tc.path, code, body)
		}
	}
}

func TestPayWithoutShiftAndCredit(t *testing.T) {
	f := newFixture(t)
	c := f.cashier(t)
	id := f.orderWithItem(t, c, 2) // ₹200
	if code, body := f.call(c, "POST", "/api/v1/orders/"+id+"/pay", map[string]any{"method": "upi"}, ""); code != 409 || errCode(body) != "shift_required" {
		t.Fatalf("pay without shift: %d %v", code, body)
	}
	f.openShift(t, c)
	if code, body := f.call(c, "POST", "/api/v1/orders/"+id+"/pay", map[string]any{"method": "credit"}, ""); code != 400 {
		t.Fatalf("credit without customer: %d %v", code, body)
	}
	if code, body := f.call(c, "POST", "/api/v1/orders/"+id+"/pay", map[string]any{"method": "credit", "customer_id": "c-nope"}, ""); code != 400 {
		t.Fatalf("credit with unknown customer: %d %v", code, body)
	}
	cust := f.must(t, 201, c, "POST", "/api/v1/customers", map[string]any{"name": "Asha", "phone": "9820000000"})
	o := f.must(t, 200, c, "POST", "/api/v1/orders/"+id+"/pay", map[string]any{"method": "credit", "customer_id": cust["id"]})
	if o["payment_method"] != "credit" || o["customer_id"] != cust["id"] {
		t.Fatalf("credit order = %v", o)
	}
	list := f.must(t, 200, c, "GET", "/api/v1/customers?q=Asha", nil)
	got := list["customers"].([]any)[0].(map[string]any)
	if num(got["outstanding_paise"]) != 20000 {
		t.Fatalf("customer outstanding = %v, want 20000", got["outstanding_paise"])
	}
	sh := f.shift(t, c)
	if num(sh["cash_sales_paise"])+num(sh["upi_sales_paise"])+num(sh["card_sales_paise"]) != 0 {
		t.Fatalf("credit sale must not hit the drawer: %v", sh)
	}
}

func TestDeletedMenuItemKeepsBillName(t *testing.T) {
	f := newFixture(t)
	c := f.cashier(t)
	mgr := f.manager(t)
	id := f.orderWithItem(t, c, 1)
	f.must(t, 200, mgr, "PATCH", "/api/v1/menu/"+f.item, map[string]any{"name": "Dal Tadka"})
	f.must(t, 200, mgr, "DELETE", "/api/v1/menu/"+f.item, nil)
	o := f.must(t, 200, c, "GET", "/api/v1/orders/"+id, nil)
	line := o["items"].([]any)[0].(map[string]any)
	if line["name"] != "Dal Fry" {
		t.Fatalf("bill line renamed to %v; snapshot must keep the sold name", line["name"])
	}
	menu := f.must(t, 200, c, "GET", "/api/v1/menu", nil)
	if n := len(menu["menu_items"].([]any)); n != 0 {
		t.Fatalf("deleted item still on the menu (%d items)", n)
	}
	if code, body := f.call(c, "POST", "/api/v1/orders/"+id+"/items", map[string]any{"menu_item_id": f.item}, ""); code != 409 {
		t.Fatalf("ordering a deleted item: %d %v", code, body)
	}
}

func TestQtyBumpOnFiredLineAddsDelta(t *testing.T) {
	f := newFixture(t)
	c := f.cashier(t)
	id := f.orderWithItem(t, c, 1)
	f.must(t, 201, c, "POST", "/api/v1/orders/"+id+"/kot", map[string]any{})
	o := f.must(t, 200, c, "GET", "/api/v1/orders/"+id, nil)
	line := o["items"].([]any)[0].(map[string]any)["id"].(string)
	body := f.must(t, 200, c, "PATCH", "/api/v1/orders/"+id+"/items/"+line, map[string]any{"quantity": 3})
	if body["item_id"] == nil || body["item_id"] == line {
		t.Fatalf("expected a new delta line id, got %v", body["item_id"])
	}
	kot := f.must(t, 201, c, "POST", "/api/v1/orders/"+id+"/kot", map[string]any{})
	items := kot["items"].([]any)
	if len(items) != 1 || num(items[0].(map[string]any)["quantity"]) != 2 {
		t.Fatalf("second KOT should fire exactly the +2 delta: %v", items)
	}
	if num(body["grand_total_paise"]) != 30000 {
		t.Fatalf("total = %v, want 30000", body["grand_total_paise"])
	}
}

// ---- reports ----

func TestRangeReportRefundsAndISTBoundary(t *testing.T) {
	f := newFixture(t)
	c := f.cashier(t)
	f.openShift(t, c)
	a := f.orderWithItem(t, c, 1) // ₹100, paid 23:30 IST on 9 Oct
	b := f.orderWithItem(t, c, 2) // ₹200, paid 00:30 IST on 10 Oct
	f.must(t, 200, c, "POST", "/api/v1/orders/"+a+"/pay", map[string]any{"method": "upi"})
	f.must(t, 200, c, "POST", "/api/v1/orders/"+b+"/pay", map[string]any{"method": "upi"})
	f.must(t, 200, c, "POST", "/api/v1/orders/"+a+"/refund", map[string]any{
		"amount_paise": 4000, "reason": "cold", "mode": "upi", "manager_pin": "9999",
	})
	db := f.e.st.DB
	for _, q := range []struct {
		sql  string
		args []any
	}{
		{`UPDATE orders SET paid_at = '2026-10-09T18:00:00.000000Z' WHERE id = ?`, []any{a}},
		{`UPDATE orders SET paid_at = '2026-10-09T19:00:00.000000Z' WHERE id = ?`, []any{b}},
		{`UPDATE refunds SET ts = '2026-10-09T18:10:00.000000Z' WHERE order_id = ?`, []any{a}},
	} {
		if _, err := db.Exec(q.sql, q.args...); err != nil {
			t.Fatal(err)
		}
	}
	adm := f.admin(t)
	rep := f.must(t, 200, adm, "GET", "/api/v1/reports/dashboard?from=2026-10-09&to=2026-10-09", nil)
	if num(rep["sales_paise"]) != 10000 || num(rep["order_count"]) != 1 {
		t.Fatalf("9 Oct IST: sales=%v count=%v, want 10000/1 (00:30 IST on the 10th excluded)", rep["sales_paise"], rep["order_count"])
	}
	if num(rep["refunds_paise"]) != 4000 || num(rep["net_sales_paise"]) != 6000 {
		t.Fatalf("refunds=%v net=%v, want 4000/6000", rep["refunds_paise"], rep["net_sales_paise"])
	}
	top := rep["top_items"].([]any)
	if len(top) != 1 || top[0].(map[string]any)["name"] != "Dal Fry" {
		t.Fatalf("top_items = %v", top)
	}
	cats := rep["top_categories"].([]any)
	if len(cats) != 1 || cats[0].(map[string]any)["category"] != "Mains" {
		t.Fatalf("top_categories = %v (want real category names)", cats)
	}
	rep = f.must(t, 200, adm, "GET", "/api/v1/reports/dashboard?from=2026-10-10&to=2026-10-10", nil)
	if num(rep["sales_paise"]) != 20000 || num(rep["refunds_paise"]) != 0 {
		t.Fatalf("10 Oct IST: %v / %v", rep["sales_paise"], rep["refunds_paise"])
	}
	// GET /orders honours the same outlet-timezone day window.
	list := f.must(t, 200, adm, "GET", "/api/v1/orders?status=completed,refunded&from=2026-10-10&to=2026-10-10", nil)
	if n := len(list["orders"].([]any)); n != 1 {
		t.Fatalf("orders on 10 Oct IST = %d, want 1", n)
	}
}

// ---- entitlement ----

func TestEntitlementHonoursTrialEnd(t *testing.T) {
	e := newEnv(t)
	org := e.register(t, fmt.Sprintf("trial-end-%d@test", time.Now().UnixNano()))
	past := time.Now().UTC().AddDate(0, 0, -30).Format("2006-01-02T15:04:05.000000Z")
	// Status still says trial (the daily job has not run) but the date passed.
	if _, err := e.st.DB.Exec(`UPDATE org_subscriptions SET trial_ends_at = ? WHERE org_id = ?`, past, org.OrgID); err != nil {
		t.Fatal(err)
	}
	e.staffLoginAsAdmin(t, org)
	if code, body := e.do(t, "POST", "/api/v1/orders", map[string]any{"type": "takeaway"}, true); code != 402 {
		t.Fatalf("expired trial write = %d %v, want 402", code, body)
	}
}

func TestKOTLineCarriesNote(t *testing.T) {
	f := newFixture(t)
	c := f.cashier(t)
	o := f.must(t, 201, c, "POST", "/api/v1/orders", map[string]any{"type": "takeaway"})
	id := o["id"].(string)
	f.must(t, 201, c, "POST", "/api/v1/orders/"+id+"/items",
		map[string]any{"menu_item_id": f.item, "quantity": 1, "note": "extra spicy"})
	f.must(t, 201, c, "POST", "/api/v1/orders/"+id+"/kot", map[string]any{})
	list := f.must(t, 200, c, "GET", "/api/v1/kots", nil)
	kots := list["kots"].([]any)
	line := kots[0].(map[string]any)["items"].([]any)[0].(map[string]any)
	if line["note"] != "extra spicy" {
		t.Fatalf("KDS ticket line lost the note: %v", line)
	}
	if mods, ok := line["modifiers"].([]any); !ok || len(mods) != 0 {
		t.Fatalf("modifiers should be an empty list, got %v", line["modifiers"])
	}
}
