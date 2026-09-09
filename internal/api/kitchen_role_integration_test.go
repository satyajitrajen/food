package api_test

// Integration coverage for the kitchen display role, the admin-only overall
// revenue dashboard, dining sections on settings, and guest phone on PATCH.

import (
	"fmt"
	"testing"
)

func (e *env) loginAs(t *testing.T, staffID, pin string) {
	t.Helper()
	code, body := e.do(t, "POST", "/api/v1/auth/login", map[string]string{
		"staff_id": staffID, "pin": pin, "outlet_id": "out-01",
	}, false)
	if code != 200 {
		t.Fatalf("login %s failed: %d %v", staffID, code, body)
	}
	token, _ := body["token"].(string)
	if token == "" {
		t.Fatalf("no token for %s: %v", staffID, body)
	}
	e.token = token
}

// Kitchen is display-only: it can read the board and drive KOT status, but
// every money/back-office write is rejected (DenyRoles).
func TestKitchenDisplayOnly(t *testing.T) {
	e := newEnv(t)
	e.login(t) // cashier st-01

	// Cashier sets up an order + KOT.
	code, body := e.do(t, "POST", "/api/v1/orders?outlet_id=out-01", map[string]any{"type": "takeaway"}, true)
	if code != 201 {
		t.Fatalf("order create failed: %d %v", code, body)
	}
	orderID := body["id"].(string)
	code, _ = e.do(t, "POST", "/api/v1/orders/"+orderID+"/items?outlet_id=out-01", map[string]any{
		"menu_item_id": "m-01", "quantity": 1,
	}, true)
	if code != 201 {
		t.Fatalf("item add failed: %d", code)
	}
	code, _ = e.do(t, "POST", "/api/v1/orders/"+orderID+"/kot?outlet_id=out-01", map[string]any{}, true)
	if code != 201 {
		t.Fatalf("kot fire failed: %d", code)
	}

	e.loginAs(t, "st-06", "5555") // kitchen

	// Reads the KDS needs.
	if c, _ := e.do(t, "GET", "/api/v1/kots?outlet_id=out-01", nil, true); c != 200 {
		t.Fatalf("kitchen kots list: expected 200, got %d", c)
	}
	if c, _ := e.do(t, "GET", "/api/v1/orders?outlet_id=out-01", nil, true); c != 200 {
		t.Fatalf("kitchen orders list: expected 200, got %d", c)
	}

	// KOT FSM transitions work from the kitchen terminal.
	code, body = e.do(t, "GET", "/api/v1/kots?outlet_id=out-01", nil, true)
	kots, _ := body["kots"].([]any)
	if len(kots) == 0 {
		t.Fatal("no kots returned")
	}
	kotID := kots[0].(map[string]any)["id"].(string)
	if c, _ := e.do(t, "PATCH", "/api/v1/kots/"+kotID, map[string]any{"status": "preparing"}, true); c != 200 {
		t.Fatalf("kot -> preparing by kitchen: expected 200, got %d", c)
	}
	if c, _ := e.do(t, "PATCH", "/api/v1/kots/"+kotID, map[string]any{"status": "ready"}, true); c != 200 {
		t.Fatalf("kot -> ready by kitchen: expected 200, got %d", c)
	}

	// Every write endpoint is denied to kitchen.
	denied := []struct {
		method, path string
		body         map[string]any
	}{
		{"POST", "/api/v1/orders?outlet_id=out-01", map[string]any{"type": "takeaway"}},
		{"PATCH", "/api/v1/orders/" + orderID, map[string]any{"guest_count": 4}},
		{"POST", "/api/v1/orders/" + orderID + "/pay?outlet_id=out-01", map[string]any{"method": "cash", "amount_received_paise": 100}},
		{"POST", "/api/v1/orders/" + orderID + "/refund", map[string]any{"amount_paise": 100, "reason": "x", "mode": "cash"}},
		{"POST", "/api/v1/shifts/open?outlet_id=out-01", map[string]any{"opening_paise": 0}},
		{"POST", "/api/v1/expenses?outlet_id=out-01", map[string]any{"title": "x", "amount_paise": 100, "category": "misc", "method": "Cash"}},
		{"POST", "/api/v1/tables?outlet_id=out-01", map[string]any{"table_number": "T99", "seats": 2, "floor": "Garden"}},
		{"PUT", "/api/v1/settings?outlet_id=out-01", map[string]any{"restaurant_name": "x"}},
		{"POST", "/api/v1/auth/verify-manager-pin", map[string]any{"pin": "9999"}},
	}
	for _, tc := range denied {
		if c, b := e.do(t, tc.method, tc.path, tc.body, true); c != 403 {
			t.Fatalf("%s %s: expected 403 for kitchen, got %d %v", tc.method, tc.path, c, b)
		}
	}
}

// The overall revenue dashboard is admin-only; kitchen is also denied via the
// write/back-office group even though this is a read.
func TestDashboardAdminOnly(t *testing.T) {
	e := newEnv(t)
	e.login(t) // cashier
	if c, _ := e.do(t, "GET", "/api/v1/reports/dashboard?outlet_id=out-01", nil, true); c != 403 {
		t.Fatalf("cashier dashboard: expected 403, got %d", c)
	}
	e.loginAs(t, "st-02", "9999") // manager
	if c, _ := e.do(t, "GET", "/api/v1/reports/dashboard?outlet_id=out-01", nil, true); c != 403 {
		t.Fatalf("manager dashboard: expected 403, got %d", c)
	}
	e.loginAs(t, "st-06", "5555") // kitchen
	if c, _ := e.do(t, "GET", "/api/v1/reports/dashboard?outlet_id=out-01", nil, true); c != 403 {
		t.Fatalf("kitchen dashboard: expected 403, got %d", c)
	}
	e.loginAs(t, "st-03", "0000") // admin
	if c, _ := e.do(t, "GET", "/api/v1/reports/dashboard?outlet_id=out-01", nil, true); c != 200 {
		t.Fatalf("admin dashboard: expected 200, got %d", c)
	}
}

// Dining sections (Garden / AC Dining / Bar) round-trip through settings.
func TestSettingsSectionsRoundTrip(t *testing.T) {
	e := newEnv(t)
	e.loginAs(t, "st-02", "9999") // manager

	sections := []any{"Garden", "AC Dining", "Bar"}
	code, body := e.do(t, "PUT", "/api/v1/settings?outlet_id=out-01", map[string]any{
		"restaurant_name": "Test Resto",
		"sections":        sections,
	}, true)
	if code != 200 {
		t.Fatalf("settings put with sections failed: %d %v", code, body)
	}
	code, body = e.do(t, "GET", "/api/v1/settings?outlet_id=out-01", nil, true)
	if code != 200 {
		t.Fatalf("settings read failed: %d", code)
	}
	got, _ := body["sections"].([]any)
	if len(got) != 3 {
		t.Fatalf("sections = %v, want 3 entries", got)
	}
	for i, want := range sections {
		if got[i] != want {
			t.Fatalf("sections[%d] = %v, want %v (full: %v)", i, got[i], want, got)
		}
	}
}

// Guest phone captured at the table must persist via PATCH /orders.
func TestPatchOrderCustomerPhone(t *testing.T) {
	e := newEnv(t)
	e.login(t) // cashier

	code, body := e.do(t, "POST", "/api/v1/orders?outlet_id=out-01", map[string]any{"type": "dine_in", "table_id": "t-01"}, true)
	if code != 201 {
		t.Fatalf("order create failed: %d %v", code, body)
	}
	orderID := body["id"].(string)

	phone := "+91 98220 11223"
	code, _ = e.do(t, "PATCH", "/api/v1/orders/"+orderID, map[string]any{
		"customer_name": "Amit", "customer_phone": phone, "guest_count": 2,
	}, true)
	if code != 200 {
		t.Fatalf("patch customer phone failed: %d", code)
	}
	code, body = e.do(t, "GET", "/api/v1/orders?outlet_id=out-01", nil, true)
	if code != 200 {
		t.Fatalf("orders list failed: %d", code)
	}
	for _, o := range body["orders"].([]any) {
		order := o.(map[string]any)
		if order["id"] != orderID {
			continue
		}
		if got, _ := order["customer_phone"].(string); got != phone {
			t.Fatalf("customer_phone = %q, want %q", got, phone)
		}
		if got, _ := order["customer_name"].(string); got != "Amit" {
			t.Fatalf("customer_name = %q, want Amit", got)
		}
		return
	}
	t.Fatal(fmt.Sprintf("order %s not found after patch", orderID))
}
