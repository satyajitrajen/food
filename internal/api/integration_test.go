package api_test

// End-to-end integration suite: seed → login → tables → order → items →
// KOT → pay → refund → shift open/close → Z-report. Runs against SQLite
// in a temp directory through the real HTTP stack.

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"foodpos/backend/internal/api"
	"foodpos/backend/internal/auth"
	"foodpos/backend/internal/config"
	"foodpos/backend/internal/db"
	"foodpos/backend/internal/store"
	"foodpos/backend/internal/ws"
)

type env struct {
	ts     *httptest.Server
	client *http.Client
	token  string
}

func newEnv(t *testing.T) *env {
	t.Helper()
	dsn := os.Getenv("FOODPOS_TEST_DSN")
	if dsn == "" {
		dsn = "postgres://foodpos:foodpos@localhost/foodpos_test?sslmode=disable"
	}
	database, err := db.Open(dsn)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = database.Close() })
	if err := db.Migrate(database); err != nil {
		t.Fatal(err)
	}
	st := store.New(database)
	mgr := auth.New("test-secret", 4)
	hub := ws.NewHub(mgr)
	tickets := auth.NewTicketStore(auth.SSETicketTTL)
	hub.SetTicketStore(tickets)
	seedServer(st, mgr)

	upTmp, err := os.MkdirTemp("", "foodpos-media-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(upTmp) })

	srv := &api.Server{Store: st, Auth: mgr, Hub: hub, Tickets: tickets, Cfg: config.Load(), UploadDir: upTmp}
	ts := httptest.NewServer(srv.Routes())
	t.Cleanup(ts.Close)
	return &env{ts: ts, client: ts.Client()}
}

// seedServer mirrors main's seed() with a minimal staff+table+menu set.
func seedServer(st *store.Store, mgr *auth.Manager) {
	st.DB.Exec(`INSERT INTO outlets (id, name, terminal) VALUES ('out-01', 'Test Outlet', 'POS-01')`)
	hash, _ := mgr.HashPIN("1234")
	st.DB.Exec(`INSERT INTO staff (id, name, role, pin_hash, is_active) VALUES ('st-01', 'Rahul', 'cashier', ?, 1)`, hash)
	hash2, _ := mgr.HashPIN("9999")
	st.DB.Exec(`INSERT INTO staff (id, name, role, pin_hash, is_active) VALUES ('st-02', 'Priya', 'manager', ?, 1)`, hash2)
	hash3, _ := mgr.HashPIN("0000")
	st.DB.Exec(`INSERT INTO staff (id, name, role, pin_hash, is_active) VALUES ('st-03', 'Vikram', 'admin', ?, 1)`, hash3)
	hash4, _ := mgr.HashPIN("5555")
	st.DB.Exec(`INSERT INTO staff (id, name, role, pin_hash, is_active) VALUES ('st-06', 'Chef', 'kitchen', ?, 1)`, hash4)
	st.DB.Exec(`INSERT INTO tables (id, outlet_id, table_number, seats, floor, status) VALUES ('t-01', 'out-01', 'T01', 4, 'Ground', 'available')`)
	st.DB.Exec(`INSERT INTO tables (id, outlet_id, table_number, seats, floor, status) VALUES ('t-02', 'out-01', 'T02', 2, 'Ground', 'available')`)
	st.DB.Exec(`INSERT INTO menu_categories (id, outlet_id, name) VALUES ('cat-1', 'out-01', 'Starters')`)
	st.DB.Exec(`INSERT INTO menu_items (id, outlet_id, category_id, name, price_paise, is_veg, is_available) VALUES ('m-01', 'out-01', 'cat-1', 'Paneer Tikka', 28000, 1, 1)`)
	st.DB.Exec(`INSERT INTO modifier_groups (id, menu_item_id, name, is_multi_select, is_required) VALUES ('mg-1', 'm-01', 'Add-ons', 1, 0)`)
	st.DB.Exec(`INSERT INTO modifier_items (id, group_id, name, price_paise) VALUES ('mo-1', 'mg-1', 'Extra Chutney', 2000)`)
	st.DB.Exec(`INSERT INTO settings (outlet_id, restaurant_name) VALUES ('out-01', 'Test Resto')`)
}

func (e *env) do(t *testing.T, method, path string, body any, auth bool) (int, map[string]any) {
	t.Helper()
	var buf bytes.Buffer
	if body != nil {
		_ = json.NewEncoder(&buf).Encode(body)
	}
	req, err := http.NewRequest(method, e.ts.URL+path, &buf)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	if auth && e.token != "" {
		req.Header.Set("Authorization", "Bearer "+e.token)
	}
	res, err := e.client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	var out map[string]any
	_ = json.NewDecoder(res.Body).Decode(&out)
	return res.StatusCode, out
}

func (e *env) login(t *testing.T) {
	t.Helper()
	code, body := e.do(t, "POST", "/api/v1/auth/login", map[string]string{
		"staff_id": "st-01", "pin": "1234", "outlet_id": "out-01",
	}, false)
	if code != 200 {
		t.Fatalf("login failed: %d %v", code, body)
	}
	token, _ := body["token"].(string)
	if token == "" {
		t.Fatalf("no token in login response: %v", body)
	}
	e.token = token
}

func TestFullOrderLifecycle(t *testing.T) {
	e := newEnv(t)
	e.login(t)

	// Health + unauthorized access
	if code, _ := e.do(t, "GET", "/healthz", nil, false); code != 200 {
		t.Fatal("healthz failed")
	}
	if code, _ := e.do(t, "GET", "/api/v1/tables?outlet_id=out-01", nil, false); code != 401 {
		t.Fatal("expected 401 without token")
	}

	// Tables list
	code, body := e.do(t, "GET", "/api/v1/tables?outlet_id=out-01", nil, true)
	if code != 200 {
		t.Fatalf("tables list failed: %d", code)
	}

	// Create dine-in order on T01
	code, body = e.do(t, "POST", "/api/v1/orders?outlet_id=out-01", map[string]any{
		"type": "dine_in", "table_id": "t-01", "guest_count": 3,
	}, true)
	if code != 201 {
		t.Fatalf("order create failed: %d %v", code, body)
	}
	orderID, _ := body["id"].(string)
	if orderID == "" {
		t.Fatalf("no order id: %v", body)
	}

	// Double-book the same table → 409
	code, _ = e.do(t, "POST", "/api/v1/orders?outlet_id=out-01", map[string]any{
		"type": "dine_in", "table_id": "t-01",
	}, true)
	if code != 409 {
		t.Fatalf("expected table_occupied 409, got %d", code)
	}

	// Add item without modifier
	code, body = e.do(t, "POST", "/api/v1/orders/"+orderID+"/items", map[string]any{
		"menu_item_id": "m-01", "quantity": 2,
	}, true)
	if code != 201 {
		t.Fatalf("add item failed: %d %v", code, body)
	}
	// 2 × ₹280 = ₹560 → 5% GST = ₹28 → total ₹588 (58800 paise)
	if got := int64(body["grand_total_paise"].(float64)); got != 58800 {
		t.Fatalf("grand total = %d, want 58800", got)
	}

	// Add item WITH modifier (+₹20)
	code, body = e.do(t, "POST", "/api/v1/orders/"+orderID+"/items", map[string]any{
		"menu_item_id": "m-01", "quantity": 1,
		"modifiers": []map[string]any{{"modifier_item_id": "mo-1"}},
	}, true)
	if code != 201 {
		t.Fatalf("add modified item failed: %d %v", code, body)
	}
	// subtotal 580+300=880... wait: 2×280=560 + (280+20)=300 → 860 → GST 43 → 90300
	if got := int64(body["grand_total_paise"].(float64)); got != 90300 {
		t.Fatalf("grand total with modifier = %d, want 90300", got)
	}

	// Open shift (cashier)
	code, body = e.do(t, "POST", "/api/v1/shifts/open?outlet_id=out-01", map[string]any{
		"opening_paise": 500000,
	}, true)
	if code != 201 {
		t.Fatalf("shift open failed: %d %v", code, body)
	}

	// Second open shift → conflict
	if code, _ = e.do(t, "POST", "/api/v1/shifts/open?outlet_id=out-01", map[string]any{"opening_paise": 1}, true); code != 409 {
		t.Fatalf("expected shift_already_open 409, got %d", code)
	}

	// Fire KOT
	code, body = e.do(t, "POST", "/api/v1/orders/"+orderID+"/kot", map[string]any{}, true)
	if code != 201 {
		t.Fatalf("KOT fire failed: %d %v", code, body)
	}
	kotID, _ := body["id"].(string)

	// KOT FSM: new → served is illegal
	code, _ = e.do(t, "PATCH", "/api/v1/kots/"+kotID, map[string]string{"status": "served"}, true)
	if code != 409 {
		t.Fatalf("expected invalid KOT transition 409, got %d", code)
	}
	// new → preparing is legal
	code, _ = e.do(t, "PATCH", "/api/v1/kots/"+kotID, map[string]string{"status": "preparing"}, true)
	if code != 200 {
		t.Fatalf("legal KOT transition failed: %d", code)
	}

	// Cash underpayment → rejected
	code, _ = e.do(t, "POST", "/api/v1/orders/"+orderID+"/pay", map[string]any{
		"method": "cash", "amount_received_paise": 100,
	}, true)
	if code != 400 {
		t.Fatalf("expected short_payment 400, got %d", code)
	}

	// Exact payment (cash, change 0)
	code, body = e.do(t, "POST", "/api/v1/orders/"+orderID+"/pay", map[string]any{
		"method": "cash", "amount_received_paise": 90300,
	}, true)
	if code != 200 {
		t.Fatalf("pay failed: %d %v", code, body)
	}
	if body["status"] != "completed" {
		t.Fatalf("order not completed: %v", body["status"])
	}

	// Table freed
	code, body = e.do(t, "GET", "/api/v1/tables?outlet_id=out-01", nil, true)
	tables := body["tables"].([]any)
	t01 := tables[0].(map[string]any)
	if t01["status"] != "available" {
		t.Fatalf("table not freed: %v", t01)
	}

	// Shift picked up cash sales
	code, body = e.do(t, "GET", "/api/v1/shifts/current?outlet_id=out-01", nil, true)
	shift := body["shift"].(map[string]any)
	if got := int64(shift["cash_sales_paise"].(float64)); got != 90300 {
		t.Fatalf("shift cash sales = %d, want 90300", got)
	}

	// Refund: over-refund rejected, then valid partial cash refund.
	// Refunds are manager-gated (FR-A3) — the PIN is part of the request.
	code, _ = e.do(t, "POST", "/api/v1/orders/"+orderID+"/refund", map[string]any{
		"amount_paise": 999999, "reason": "test", "mode": "cash", "manager_pin": "9999",
	}, true)
	if code != 400 {
		t.Fatalf("expected refund_exceeds_paid 400, got %d", code)
	}
	code, _ = e.do(t, "POST", "/api/v1/orders/"+orderID+"/refund", map[string]any{
		"amount_paise": 10000, "reason": "wrong item", "mode": "cash", "manager_pin": "9999",
	}, true)
	if code != 200 {
		t.Fatal("valid refund failed")
	}

	// Close shift with counted cash and check the Z-report
	code, body = e.do(t, "POST", "/api/v1/shifts/current/close?outlet_id=out-01", map[string]any{
		"counted_paise": 583300, // 500000 + 90300 - 10000 - 700(?) → counted minus
	}, true)
	if code != 200 {
		t.Fatalf("close shift failed: %d %v", code, body)
	}
	// expected = 500000 + 90300(cash sales) - 10000(cash refund) = 580300; difference = +3000
	shiftID := body["id"].(string)
	code, body = e.do(t, "GET", "/api/v1/reports/shift/"+shiftID+"/zreport", nil, true)
	if code != 200 {
		t.Fatalf("zreport failed: %d", code)
	}
	if got := int64(body["expected_cash_paise"].(float64)); got != 580300 {
		t.Fatalf("expected cash = %d, want 580300", got)
	}
	if got := int64(body["difference_paise"].(float64)); got != 3000 {
		t.Fatalf("difference = %d, want 3000", got)
	}
}

func TestIdempotentOrderCreate(t *testing.T) {
	e := newEnv(t)
	e.login(t)
	req := func() (int, map[string]any) {
		var buf bytes.Buffer
		_ = json.NewEncoder(&buf).Encode(map[string]any{"type": "takeaway"})
		req2, _ := http.NewRequest("POST", e.ts.URL+"/api/v1/orders?outlet_id=out-01", &buf)
		req2.Header.Set("Content-Type", "application/json")
		req2.Header.Set("Authorization", "Bearer "+e.token)
		req2.Header.Set("Idempotency-Key", "key-1")
		res, err := e.client.Do(req2)
		if err != nil {
			t.Fatal(err)
		}
		defer res.Body.Close()
		var out map[string]any
		_ = json.NewDecoder(res.Body).Decode(&out)
		return res.StatusCode, out
	}
	code1, b1 := req()
	code2, b2 := req()
	if code1 != 201 || code2 != 201 {
		t.Fatalf("idempotent create failed: %d %d", code1, code2)
	}
	if b1["id"] != b2["id"] {
		t.Fatalf("idempotency key returned different orders: %v vs %v", b1["id"], b2["id"])
	}
}

func TestRoleGate(t *testing.T) {
	e := newEnv(t)
	e.login(t) // cashier
	code, _ := e.do(t, "POST", "/api/v1/staff?outlet_id=out-01", map[string]any{
		"name": "X", "role": "waiter", "pin": "4321",
	}, true)
	if code != 403 {
		t.Fatalf("cashier creating staff should be 403, got %d", code)
	}

	// manager login can
	var buf bytes.Buffer
	_ = json.NewEncoder(&buf).Encode(map[string]string{"staff_id": "st-02", "pin": "9999"})
	req, _ := http.NewRequest("POST", e.ts.URL+"/api/v1/auth/login", &buf)
	res, err := e.client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	var lr map[string]any
	_ = json.NewDecoder(res.Body).Decode(&lr)
	res.Body.Close()
	mgrToken := lr["token"].(string)

	old := e.token
	e.token = mgrToken
	code, body := e.do(t, "POST", "/api/v1/staff?outlet_id=out-01", map[string]any{
		"name": "New Waiter", "role": "waiter", "pin": "4321",
	}, true)
	e.token = old
	if code != 201 {
		t.Fatalf("manager create staff failed: %d %v", code, body)
	}
}

func TestDiscountClampEndpoint(t *testing.T) {
	e := newEnv(t)
	e.login(t)
	_, body := e.do(t, "POST", "/api/v1/orders?outlet_id=out-01", map[string]any{"type": "takeaway"}, true)
	orderID := body["id"].(string)
	_, _ = e.do(t, "POST", "/api/v1/orders/"+orderID+"/items", map[string]any{
		"menu_item_id": "m-01", "quantity": 1,
	}, true)
	// 150% discount is clamped to 100% by the service layer, not rejected.
	// Above the 20% threshold a manager PIN is required (FR-A3).
	code, body := e.do(t, "PATCH", "/api/v1/orders/"+orderID, map[string]any{
		"discount_percent": 150, "manager_pin": "9999",
	}, true)
	if code != 200 {
		t.Fatalf("patch order failed: %d %v", code, body)
	}
	if got := int64(body["discount_paise"].(float64)); got != 28000 {
		t.Fatalf("discount = %d, want clamped 28000", got)
	}
	// FR-O3: the discount clamps to the SUBTOTAL only; per-bill charges
	// (packaging default ₹25 from settings) are added after the discount,
	// so the grand total is the charge, not zero.
	if got := int64(body["grand_total_paise"].(float64)); got != 2500 {
		t.Fatalf("grand total after 100%% discount = %d, want 2500 (packaging default)", got)
	}
	fmt.Println("done")
}

func TestPurchasesAndStock(t *testing.T) {
	e := newEnv(t)
	e.login(t)

	// Create an inventory item (manager-gated; cashier is fine here since we
	// only need a row — create via manager PIN session below).
	var buf bytes.Buffer
	_ = json.NewEncoder(&buf).Encode(map[string]string{"staff_id": "st-02", "pin": "9999"})
	req, _ := http.NewRequest("POST", e.ts.URL+"/api/v1/auth/login", &buf)
	res, err := e.client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	var lr map[string]any
	_ = json.NewDecoder(res.Body).Decode(&lr)
	res.Body.Close()
	old := e.token
	e.token = lr["token"].(string)
	code, body := e.do(t, "POST", "/api/v1/inventory?outlet_id=out-01", map[string]any{
		"name": "Rice", "unit": "KG", "stock": 10, "min_stock": 2, "cost_paise": 4500,
	}, true)
	if code != 201 {
		t.Fatalf("inventory create failed: %d %v", code, body)
	}
	itemID := body["id"].(string)
	e.token = old

	// Supplier + pending purchase with stock intake
	code, body = e.do(t, "POST", "/api/v1/suppliers?outlet_id=out-01", map[string]any{
		"name": "Agro Foods", "mobile": "9876543210",
	}, true)
	if code != 201 {
		t.Fatalf("supplier create failed: %d %v", code, body)
	}
	supID := body["id"].(string)

	code, body = e.do(t, "POST", "/api/v1/purchases?outlet_id=out-01", map[string]any{
		"invoice_no": "PI-1", "supplier_id": supID, "status": "pending", "total_paise": 90000,
		"items": []map[string]any{{"inventory_item_id": itemID, "name": "Rice", "qty": 5.0, "unit_cost_paise": 4500}},
	}, true)
	if code != 201 {
		t.Fatalf("purchase create failed: %d %v", code, body)
	}
	purID := body["id"].(string)

	// Stock intake posted
	code, body = e.do(t, "GET", "/api/v1/inventory?outlet_id=out-01", nil, true)
	items := body["inventory"].([]any)
	if got := items[0].(map[string]any)["stock"].(float64); got != 15 {
		t.Fatalf("stock after purchase = %v, want 15", got)
	}

	// Supplier outstanding went up by the pending total
	code, body = e.do(t, "GET", "/api/v1/suppliers?outlet_id=out-01", nil, true)
	sup := body["suppliers"].([]any)[0].(map[string]any)
	if got := int64(sup["outstanding_paise"].(float64)); got != 90000 {
		t.Fatalf("supplier outstanding = %d, want 90000", got)
	}

	// Stock log shows the intake
	code, body = e.do(t, "GET", "/api/v1/inventory/"+itemID+"/adjustments?outlet_id=out-01", nil, true)
	if code != 200 {
		t.Fatalf("stock log failed: %d", code)
	}
	log := body["adjustments"].([]any)
	if len(log) == 0 {
		t.Fatal("no stock adjustments recorded for purchase intake")
	}
	if log[0].(map[string]any)["reason"] != "Purchase PI-1" {
		t.Fatalf("unexpected log reason: %v", log[0])
	}

	// Settle the purchase → supplier outstanding drops to 0
	code, body = e.do(t, "PATCH", "/api/v1/purchases/"+purID, map[string]any{"status": "paid"}, true)
	if code != 200 {
		t.Fatalf("purchase settle failed: %d %v", code, body)
	}
	code, body = e.do(t, "GET", "/api/v1/suppliers?outlet_id=out-01", nil, true)
	sup = body["suppliers"].([]any)[0].(map[string]any)
	if got := int64(sup["outstanding_paise"].(float64)); got != 0 {
		t.Fatalf("supplier outstanding after settle = %d, want 0", got)
	}

	// paid → pending is illegal
	code, _ = e.do(t, "PATCH", "/api/v1/purchases/"+purID, map[string]any{"status": "pending"}, true)
	if code != 409 {
		t.Fatalf("expected 409 paid→pending, got %d", code)
	}
}

func TestCustomerCredit(t *testing.T) {
	e := newEnv(t)
	e.login(t)

	code, body := e.do(t, "POST", "/api/v1/customers?outlet_id=out-01", map[string]any{
		"name": "Karan", "phone": "9812345678",
	}, true)
	if code != 201 {
		t.Fatalf("customer create failed: %d %v", code, body)
	}
	custID := body["id"].(string)

	// Credit sale ₹500
	code, body = e.do(t, "POST", "/api/v1/customers/"+custID+"/credit?outlet_id=out-01", map[string]any{
		"kind": "sale", "amount_paise": 50000, "reason": "house tab",
	}, true)
	if code != 200 {
		t.Fatalf("credit sale failed: %d %v", code, body)
	}
	if got := int64(body["outstanding_paise"].(float64)); got != 50000 {
		t.Fatalf("outstanding = %d, want 50000", got)
	}

	// Over-settlement rejected
	code, _ = e.do(t, "POST", "/api/v1/customers/"+custID+"/credit?outlet_id=out-01", map[string]any{
		"kind": "settlement", "amount_paise": 60000, "reason": "upi",
	}, true)
	if code != 400 {
		t.Fatalf("expected settlement_exceeds_outstanding 400, got %d", code)
	}

	// Valid settlement ₹200
	code, body = e.do(t, "POST", "/api/v1/customers/"+custID+"/credit?outlet_id=out-01", map[string]any{
		"kind": "settlement", "amount_paise": 20000, "reason": "upi",
	}, true)
	if code != 200 {
		t.Fatalf("settlement failed: %d %v", code, body)
	}
	if got := int64(body["outstanding_paise"].(float64)); got != 30000 {
		t.Fatalf("outstanding after settle = %d, want 30000", got)
	}

	// Missing reason rejected
	code, _ = e.do(t, "POST", "/api/v1/customers/"+custID+"/credit?outlet_id=out-01", map[string]any{
		"kind": "sale", "amount_paise": 1000, "reason": "",
	}, true)
	if code != 400 {
		t.Fatalf("expected missing_reason 400, got %d", code)
	}

	// Log has both movements
	code, body = e.do(t, "GET", "/api/v1/customers/"+custID+"/credit-log?outlet_id=out-01", nil, true)
	entries := body["entries"].([]any)
	if len(entries) != 2 {
		t.Fatalf("credit log entries = %d, want 2", len(entries))
	}
}

func TestRefreshTokenRotation(t *testing.T) {
	e := newEnv(t)
	code, body := e.do(t, "POST", "/api/v1/auth/login", map[string]string{
		"staff_id": "st-01", "pin": "1234",
	}, false)
	if code != 200 {
		t.Fatalf("login failed: %d %v", code, body)
	}
	refresh, _ := body["refresh_token"].(string)
	if refresh == "" {
		t.Fatalf("no refresh_token in login response: %v", body)
	}

	// Rotate once
	code, body = e.do(t, "POST", "/api/v1/auth/refresh", map[string]string{"refresh_token": refresh}, false)
	if code != 200 {
		t.Fatalf("refresh failed: %d %v", code, body)
	}
	newRefresh, _ := body["refresh_token"].(string)
	if newRefresh == "" || newRefresh == refresh {
		t.Fatal("refresh token was not rotated")
	}

	// Old token must be rejected (reuse detection)
	code, _ = e.do(t, "POST", "/api/v1/auth/refresh", map[string]string{"refresh_token": refresh}, false)
	if code != 401 {
		t.Fatalf("reused refresh token: expected 401, got %d", code)
	}

	// New token still valid (and rotates again)
	code, body = e.do(t, "POST", "/api/v1/auth/refresh", map[string]string{"refresh_token": newRefresh}, false)
	if code != 200 {
		t.Fatalf("rotated refresh token rejected: %d", code)
	}
	refresh2, _ := body["refresh_token"].(string)

	// Garbage token
	code, _ = e.do(t, "POST", "/api/v1/auth/refresh", map[string]string{"refresh_token": "nope"}, false)
	if code != 401 {
		t.Fatalf("garbage refresh token: expected 401, got %d", code)
	}

	// Logout revokes
	if code, _ = e.do(t, "POST", "/api/v1/auth/logout", map[string]string{"refresh_token": refresh2}, false); code != 200 {
		t.Fatal("logout failed")
	}
	if code, _ = e.do(t, "POST", "/api/v1/auth/refresh", map[string]string{"refresh_token": refresh2}, false); code != 401 {
		t.Fatal("revoked refresh token still usable")
	}
}

func TestRateLimit(t *testing.T) {
	e := newEnv(t)
	last := 0
	for i := 0; i < 30; i++ {
		code, _ := e.do(t, "POST", "/api/v1/auth/login", map[string]string{
			"staff_id": "st-01", "pin": "0000",
		}, false)
		last = code
	}
	if last != 429 {
		t.Fatalf("expected 429 after burst, got %d", last)
	}
}

// Regression: PUT /settings with no outlet_id in the body must resolve the
// outlet from the request scope (query/JWT), not try to insert an empty
// outlet_id (FK violation on settings.outlet_id).
func TestSettingsUpsertResolvesOutlet(t *testing.T) {
	e := newEnv(t)

	// Manager login (settings PUT is manager-gated).
	var buf bytes.Buffer
	_ = json.NewEncoder(&buf).Encode(map[string]string{"staff_id": "st-02", "pin": "9999"})
	req, _ := http.NewRequest("POST", e.ts.URL+"/api/v1/auth/login", &buf)
	res, err := e.client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	var lr map[string]any
	_ = json.NewDecoder(res.Body).Decode(&lr)
	res.Body.Close()
	old := e.token
	e.token = lr["token"].(string)
	t.Cleanup(func() { e.token = old })

	// Body WITHOUT outlet_id — the regression case the Flutter app sends.
	code, body := e.do(t, "PUT", "/api/v1/settings?outlet_id=out-01", map[string]any{
		"restaurant_name": "Renamed Resto",
		"gst_percent":     12.0,
	}, true)
	if code != 200 {
		t.Fatalf("settings upsert without outlet_id failed: %d %v", code, body)
	}

	// The upsert landed on the outlet's existing row (not an empty-outlet row).
	code, body = e.do(t, "GET", "/api/v1/settings?outlet_id=out-01", nil, true)
	if code != 200 {
		t.Fatalf("settings read failed: %d %v", code, body)
	}
	if got, _ := body["restaurant_name"].(string); got != "Renamed Resto" {
		t.Fatalf("restaurant_name = %q, want Renamed Resto", got)
	}
	if got := body["gst_percent"].(float64); got != 12.0 {
		t.Fatalf("gst_percent = %v, want 12", got)
	}

	// An empty scope (no query, no claim) is still rejected with 400.
	code, _ = e.do(t, "PUT", "/api/v1/settings", map[string]any{
		"restaurant_name": "No Outlet",
	}, true)
	if code != 400 {
		t.Fatalf("settings upsert without any outlet scope: expected 400, got %d", code)
	}
}

// W-caveat 2: the /ws connect uses a single-use, short-TTL ticket instead of
// the raw JWT, so nothing reusable lands in proxy access logs.
func TestWsTicket(t *testing.T) {
	e := newEnv(t)
	e.login(t)

	// Issue a ticket against the authenticated JWT.
	code, body := e.do(t, "POST", "/api/v1/ws/ticket", nil, true)
	if code != 200 {
		t.Fatalf("ws ticket failed: %d %v", code, body)
	}
	ticket, _ := body["ticket"].(string)
	if ticket == "" {
		t.Fatalf("no ticket in response: %v", body)
	}

	// A bogus ticket is rejected...
	req, _ := http.NewRequest("GET", e.ts.URL+"/api/v1/ws?outlet_id=out-01&ticket=bad-ticket", nil)
	res, err := e.client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if res.StatusCode != 401 {
		t.Fatalf("bad ticket: expected 401, got %d", res.StatusCode)
	}
	res.Body.Close()

	// The real ticket opens the stream...
	req, _ = http.NewRequest("GET", e.ts.URL+"/api/v1/ws?outlet_id=out-01&ticket="+ticket, nil)
	res, err = e.client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != 200 {
		t.Fatalf("ticket connect: expected 200, got %d", res.StatusCode)
	}
	buf := make([]byte, 64)
	_, _ = res.Body.Read(buf)
	if !strings.Contains(string(buf), ": connected") {
		t.Fatalf("stream did not open with : connected, got %q", string(buf))
	}
	res.Body.Close()

	// ...and is consumed — reuse must fail.
	req2, _ := http.NewRequest("GET", e.ts.URL+"/api/v1/ws?outlet_id=out-01&ticket="+ticket, nil)
	res2, err := e.client.Do(req2)
	if err != nil {
		t.Fatal(err)
	}
	defer res2.Body.Close()
	if res2.StatusCode != 401 {
		t.Fatalf("reused ticket: expected 401, got %d", res2.StatusCode)
	}
}

// New orders must inherit the outlet's configured GST percent and per-type
// charge defaults (packaging for takeaway/delivery, delivery for delivery),
// instead of hardcoded constants. An explicit tax_percent still wins.
func TestOrderDefaultsFromSettings(t *testing.T) {
	e := newEnv(t)

	// Manager login + reconfigure the outlet settings.
	var buf bytes.Buffer
	_ = json.NewEncoder(&buf).Encode(map[string]string{"staff_id": "st-02", "pin": "9999"})
	req, _ := http.NewRequest("POST", e.ts.URL+"/api/v1/auth/login", &buf)
	res, err := e.client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	var lr map[string]any
	_ = json.NewDecoder(res.Body).Decode(&lr)
	res.Body.Close()
	old := e.token
	e.token = lr["token"].(string)
	t.Cleanup(func() { e.token = old })

	code, body := e.do(t, "PUT", "/api/v1/settings?outlet_id=out-01", map[string]any{
		"restaurant_name": "Test Resto",
		"gst_percent":     12.0,
		"packaging_paise": 1500,
		"delivery_paise":  3000,
	}, true)
	if code != 200 {
		t.Fatalf("settings put failed: %d %v", code, body)
	}

	// Takeaway: GST + packaging defaults apply, no delivery charge.
	code, body = e.do(t, "POST", "/api/v1/orders?outlet_id=out-01", map[string]any{
		"type": "takeaway",
	}, true)
	if code != 201 {
		t.Fatalf("takeaway create failed: %d %v", code, body)
	}
	if got := body["tax_percent"].(float64); got != 12.0 {
		t.Fatalf("tax_percent = %v, want 12 (from settings)", got)
	}
	if got := int64(body["packaging_charge_paise"].(float64)); got != 1500 {
		t.Fatalf("packaging = %d, want 1500 (from settings)", got)
	}
	if got := int64(body["delivery_charge_paise"].(float64)); got != 0 {
		t.Fatalf("delivery = %d, want 0 on takeaway", got)
	}

	// Delivery: packaging + delivery defaults apply.
	code, body = e.do(t, "POST", "/api/v1/orders?outlet_id=out-01", map[string]any{
		"type": "delivery",
	}, true)
	if code != 201 {
		t.Fatalf("delivery create failed: %d %v", code, body)
	}
	if got := int64(body["delivery_charge_paise"].(float64)); got != 3000 {
		t.Fatalf("delivery = %d, want 3000 (from settings)", got)
	}

	// Dine-in with an explicit tax_percent: the explicit value wins.
	code, body = e.do(t, "POST", "/api/v1/orders?outlet_id=out-01", map[string]any{
		"type": "takeaway", "tax_percent": 8.0,
	}, true)
	if code != 201 {
		t.Fatalf("explicit-tax create failed: %d %v", code, body)
	}
	if got := body["tax_percent"].(float64); got != 8.0 {
		t.Fatalf("tax_percent = %v, want explicit 8.0", got)
	}
}

// FR-A3: the manager gate authorizes manager/admin PINs against the server's
// bcrypt store and rejects everything else.
func TestVerifyManagerPin(t *testing.T) {
	e := newEnv(t)
	e.login(t) // any authenticated staff may verify a manager PIN

	code, body := e.do(t, "POST", "/api/v1/auth/verify-manager-pin", map[string]any{
		"pin": "9999",
	}, true)
	if code != 200 {
		t.Fatalf("verify-manager-pin failed: %d %v", code, body)
	}
	if body["valid"] != true {
		t.Fatalf("manager PIN 9999 should be valid, got %v", body)
	}

	code, body = e.do(t, "POST", "/api/v1/auth/verify-manager-pin", map[string]any{
		"pin": "1234", // cashier PIN — must not pass the manager gate
	}, true)
	if code != 200 || body["valid"] != false {
		t.Fatalf("cashier PIN must not verify as manager: %d %v", code, body)
	}
}

// FR-A3 server-side gates: refunds always need a manager PIN; discounts above
// 20%/₹500 need one; cancelling an item after its KOT was sent needs one.
// Everything below the threshold stays ungated.
func TestManagerGates(t *testing.T) {
	e := newEnv(t)
	e.login(t) // cashier

	// Setup: order with an item, KOT fired, shift open.
	code, body := e.do(t, "POST", "/api/v1/orders?outlet_id=out-01", map[string]any{"type": "takeaway"}, true)
	if code != 201 {
		t.Fatalf("order create failed: %d %v", code, body)
	}
	orderID := body["id"].(string)
	code, body = e.do(t, "POST", "/api/v1/orders/"+orderID+"/items?outlet_id=out-01", map[string]any{
		"menu_item_id": "m-01", "quantity": 2,
	}, true)
	if code != 201 {
		t.Fatalf("item add failed: %d %v", code, body)
	}
	itemID := body["items"].([]any)[0].(map[string]any)["id"].(string)
	_, _ = e.do(t, "POST", "/api/v1/shifts/open?outlet_id=out-01", map[string]any{"opening_paise": 100000}, true)

	// Refund without manager PIN → 403.
	code, body = e.do(t, "POST", "/api/v1/orders/"+orderID+"/refund", map[string]any{
		"amount_paise": 1000, "reason": "wrong item", "mode": "cash",
	}, true)
	if code != 403 {
		t.Fatalf("refund without manager PIN: expected 403, got %d %v", code, body)
	}

	// Discount 25% without PIN → 403; with PIN → 200.
	code, body = e.do(t, "PATCH", "/api/v1/orders/"+orderID, map[string]any{
		"discount_percent": 25,
	}, true)
	if code != 403 {
		t.Fatalf("25%% discount without manager PIN: expected 403, got %d %v", code, body)
	}
	code, body = e.do(t, "PATCH", "/api/v1/orders/"+orderID, map[string]any{
		"discount_percent": 25, "manager_pin": "9999",
	}, true)
	if code != 200 {
		t.Fatalf("25%% discount with manager PIN failed: %d %v", code, body)
	}

	// Discount 10% is below the threshold → no PIN needed.
	code, body = e.do(t, "PATCH", "/api/v1/orders/"+orderID, map[string]any{
		"discount_percent": 10,
	}, true)
	if code != 200 {
		t.Fatalf("10%% discount should not need a PIN: %d %v", code, body)
	}

	// KOT fire → then cancelling the KOT-sent item without PIN → 403.
	code, _ = e.do(t, "POST", "/api/v1/orders/"+orderID+"/kot?outlet_id=out-01", map[string]any{}, true)
	if code != 201 {
		t.Fatalf("kot fire failed: %d", code)
	}
	code, body = e.do(t, "POST", "/api/v1/orders/"+orderID+"/items/"+itemID+"/cancel", map[string]any{
		"reason": "customer changed mind",
	}, true)
	if code != 403 {
		t.Fatalf("cancel after KOT without manager PIN: expected 403, got %d %v", code, body)
	}
	code, body = e.do(t, "POST", "/api/v1/orders/"+orderID+"/items/"+itemID+"/cancel", map[string]any{
		"reason": "customer changed mind", "manager_pin": "9999",
	}, true)
	if code != 200 {
		t.Fatalf("cancel after KOT with manager PIN failed: %d %v", code, body)
	}

	// Refund with manager PIN → 200.
	code, body = e.do(t, "POST", "/api/v1/orders/"+orderID+"/refund", map[string]any{
		"amount_paise": 1000, "reason": "wrong item", "mode": "cash", "manager_pin": "9999",
	}, true)
	if code != 200 {
		t.Fatalf("refund with manager PIN failed: %d %v", code, body)
	}
}

// B1 (FR-O3): inclusive GST — tax is extracted from the prices, not added.
func TestInclusiveGSTOrder(t *testing.T) {
	e := newEnv(t)

	// Manager turns on inclusive GST.
	var buf bytes.Buffer
	_ = json.NewEncoder(&buf).Encode(map[string]string{"staff_id": "st-02", "pin": "9999"})
	req, _ := http.NewRequest("POST", e.ts.URL+"/api/v1/auth/login", &buf)
	res, err := e.client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	var lr map[string]any
	_ = json.NewDecoder(res.Body).Decode(&lr)
	res.Body.Close()
	old := e.token
	e.token = lr["token"].(string)
	t.Cleanup(func() { e.token = old })

	code, body := e.do(t, "PUT", "/api/v1/settings?outlet_id=out-01", map[string]any{
		"restaurant_name":  "Test Resto",
		"gst_percent":      5.0,
		"is_gst_inclusive": true,
		"packaging_paise":  0,
		"delivery_paise":   0,
	}, true)
	if code != 200 {
		t.Fatalf("settings put failed: %d %v", code, body)
	}

	code, body = e.do(t, "POST", "/api/v1/orders?outlet_id=out-01", map[string]any{"type": "takeaway"}, true)
	if code != 201 {
		t.Fatalf("order create failed: %d %v", code, body)
	}
	orderID := body["id"].(string)
	if body["is_tax_inclusive"] != true {
		t.Fatalf("order should inherit is_gst_inclusive from settings")
	}
	code, body = e.do(t, "POST", "/api/v1/orders/"+orderID+"/items?outlet_id=out-01", map[string]any{
		"menu_item_id": "m-01", "quantity": 1, // 28000 paise
	}, true)
	if code != 201 {
		t.Fatalf("item add failed: %d %v", code, body)
	}
	// Extracted tax: 28000·5/105 = 1333; grand total = menu price only.
	if got := int64(body["tax_paise"].(float64)); got != 1333 {
		t.Fatalf("tax = %d, want extracted 1333", got)
	}
	if got := int64(body["grand_total_paise"].(float64)); got != 28000 {
		t.Fatalf("grand total = %d, want 28000 (inclusive)", got)
	}
}
