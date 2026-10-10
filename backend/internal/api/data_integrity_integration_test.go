package api_test

import "testing"

// Settings saved by the manager are what bills use — including 0 — and a
// change re-rates bills that are still open. Keys left out keep their value.
func TestSettingsPartialAndOpenBillsRerated(t *testing.T) {
	e := newEnv(t)
	e.loginAs(t, "st-02", "9999") // manager
	// Tests share one database: put the seeded settings back afterwards.
	t.Cleanup(func() {
		e.loginAs(t, "st-02", "9999")
		e.do(t, "PUT", "/api/v1/settings?outlet_id=out-01", map[string]any{"gst_percent": 5, "packaging_paise": 2500,
			"upi_id": "", "allow_reprint": true}, true)
	})

	// An open takeaway bill at the default 5%.
	code, ord := e.do(t, "POST", "/api/v1/orders?outlet_id=out-01", map[string]any{"type": "takeaway"}, true)
	if code != 201 {
		t.Fatalf("create order: %d %v", code, ord)
	}
	id := ord["id"].(string)
	if code, body := e.do(t, "POST", "/api/v1/orders/"+id+"/items?outlet_id=out-01",
		map[string]any{"menu_item_id": "m-01", "quantity": 1}, true); code != 201 && code != 200 {
		t.Fatalf("add item: %d %v", code, body)
	}

	// GST 0 + no packaging, sent without the printer/UPI keys.
	code, st := e.do(t, "PUT", "/api/v1/settings?outlet_id=out-01",
		map[string]any{"gst_percent": 0, "packaging_paise": 0, "upi_id": "resto@upi"}, true)
	if code != 200 || st["gst_percent"] != float64(0) {
		t.Fatalf("put settings: %d %v", code, st)
	}
	if st["restaurant_name"] != "Test Resto" {
		t.Fatalf("omitted key was wiped: %v", st["restaurant_name"])
	}
	// A later save that leaves upi_id out keeps it.
	if code, st = e.do(t, "PUT", "/api/v1/settings?outlet_id=out-01",
		map[string]any{"allow_reprint": false}, true); code != 200 || st["upi_id"] != "resto@upi" || st["gst_percent"] != float64(0) {
		t.Fatalf("partial save: %d %v", code, st)
	}

	_, got := e.do(t, "GET", "/api/v1/orders/"+id+"?outlet_id=out-01", nil, true)
	if got["tax_paise"] != float64(0) || got["grand_total_paise"] != float64(28000) {
		t.Fatalf("open bill not re-rated: tax=%v total=%v", got["tax_paise"], got["grand_total_paise"])
	}
	// New bills use it too.
	_, ord2 := e.do(t, "POST", "/api/v1/orders?outlet_id=out-01", map[string]any{"type": "takeaway"}, true)
	if ord2["tax_percent"] != float64(0) {
		t.Fatalf("new order tax_percent = %v", ord2["tax_percent"])
	}
}

func TestOrderPatchZeroValues(t *testing.T) {
	e := newEnv(t)
	e.loginAs(t, "st-02", "9999")
	_, ord := e.do(t, "POST", "/api/v1/orders?outlet_id=out-01", map[string]any{"type": "dine_in", "table_id": "t-01"}, true)
	id := ord["id"].(string)
	e.do(t, "POST", "/api/v1/orders/"+id+"/items?outlet_id=out-01", map[string]any{"menu_item_id": "m-01", "quantity": 1}, true)

	_, o := e.do(t, "PATCH", "/api/v1/orders/"+id+"?outlet_id=out-01", map[string]any{"service_percent": 10}, true)
	if o["service_charge_paise"] != float64(2800) {
		t.Fatalf("service 10%%: %v", o["service_charge_paise"])
	}
	_, o = e.do(t, "PATCH", "/api/v1/orders/"+id+"?outlet_id=out-01", map[string]any{"service_percent": 0}, true)
	if o["service_charge_paise"] != float64(0) {
		t.Fatalf("service 0%% kept the old charge: %v", o["service_charge_paise"])
	}
	if code, _ := e.do(t, "PATCH", "/api/v1/orders/"+id+"?outlet_id=out-01",
		map[string]any{"discount_percent": 5, "discount_paise": 100}, true); code != 400 {
		t.Fatalf("both discounts: want 400, got %d", code)
	}
	if code, o := e.do(t, "PATCH", "/api/v1/orders/"+id+"?outlet_id=out-01",
		map[string]any{"tax_percent": 0}, true); code != 200 || o["tax_paise"] != float64(0) {
		t.Fatalf("manager re-rate bill: %d %v", code, o["tax_paise"])
	}
	if code, o := e.do(t, "PATCH", "/api/v1/orders/"+id+"?outlet_id=out-01",
		map[string]any{"waiter_id": ""}, true); code != 200 || o["waiter_id"] != nil {
		t.Fatalf("clear waiter: %d %v", code, o["waiter_id"])
	}
	e.login(t) // cashier can't re-rate GST
	if code, _ := e.do(t, "PATCH", "/api/v1/orders/"+id+"?outlet_id=out-01",
		map[string]any{"tax_percent": 5}, true); code != 403 {
		t.Fatalf("cashier tax change: want 403, got %d", code)
	}
	// Free the table for the next test (no KOT yet, so no PIN needed).
	if code, body := e.do(t, "POST", "/api/v1/orders/"+id+"/cancel?outlet_id=out-01", map[string]any{}, true); code != 200 {
		t.Fatalf("cancel: %d %v", code, body)
	}
}

func TestCancelUnpaidOrder(t *testing.T) {
	e := newEnv(t)
	e.login(t) // cashier
	_, ord := e.do(t, "POST", "/api/v1/orders?outlet_id=out-01", map[string]any{"type": "dine_in", "table_id": "t-02"}, true)
	id := ord["id"].(string)
	e.do(t, "POST", "/api/v1/orders/"+id+"/items?outlet_id=out-01", map[string]any{"menu_item_id": "m-01", "quantity": 1}, true)
	if code, body := e.do(t, "POST", "/api/v1/orders/"+id+"/kot?outlet_id=out-01", map[string]any{}, true); code >= 300 {
		t.Fatalf("fire kot: %d %v", code, body)
	}
	// After a KOT the cashier needs a manager PIN.
	if code, _ := e.do(t, "POST", "/api/v1/orders/"+id+"/cancel?outlet_id=out-01", map[string]any{"reason": "left"}, true); code != 403 {
		t.Fatalf("cancel without pin: want 403, got %d", code)
	}
	code, o := e.do(t, "POST", "/api/v1/orders/"+id+"/cancel?outlet_id=out-01",
		map[string]any{"reason": "left", "manager_pin": "9999"}, true)
	if code != 200 || o["status"] != "cancelled" {
		t.Fatalf("cancel: %d %v", code, o)
	}
	_, tables := e.do(t, "GET", "/api/v1/tables?outlet_id=out-01", nil, true)
	for _, raw := range tables["tables"].([]any) {
		tb := raw.(map[string]any)
		if tb["id"] == "t-02" && (tb["status"] != "available" || tb["active_order_id"] != nil) {
			t.Fatalf("table not freed: %v", tb)
		}
	}
	if code, _ := e.do(t, "POST", "/api/v1/orders/"+id+"/cancel?outlet_id=out-01", map[string]any{}, true); code != 409 {
		t.Fatalf("cancel twice: want 409, got %d", code)
	}
}

func TestBackOfficeEditDelete(t *testing.T) {
	e := newEnv(t)
	e.loginAs(t, "st-02", "9999")

	// Customers
	_, c := e.do(t, "POST", "/api/v1/customers?outlet_id=out-01", map[string]any{"name": "Asha", "phone": "9876543210"}, true)
	cid := c["id"].(string)
	if code, c := e.do(t, "PATCH", "/api/v1/customers/"+cid+"?outlet_id=out-01",
		map[string]any{"name": "Asha K", "email": "a@x.in"}, true); code != 200 || c["name"] != "Asha K" {
		t.Fatalf("patch customer: %d %v", code, c)
	}
	if code, _ := e.do(t, "DELETE", "/api/v1/customers/"+cid+"?outlet_id=out-01", nil, true); code != 200 {
		t.Fatalf("delete customer: %d", code)
	}
	_, list := e.do(t, "GET", "/api/v1/customers?outlet_id=out-01", nil, true)
	for _, raw := range list["customers"].([]any) {
		if raw.(map[string]any)["id"] == cid {
			t.Fatal("deleted customer still listed")
		}
	}
	// Same phone again brings the customer back instead of failing.
	if code, body := e.do(t, "POST", "/api/v1/customers?outlet_id=out-01",
		map[string]any{"name": "Asha", "phone": "9876543210"}, true); code != 201 {
		t.Fatalf("re-add customer: %d %v", code, body)
	}

	// Suppliers
	_, sup := e.do(t, "POST", "/api/v1/suppliers?outlet_id=out-01", map[string]any{"name": "Dairy", "mobile": "9000000000"}, true)
	sid := sup["id"].(string)
	if code, s := e.do(t, "PATCH", "/api/v1/suppliers/"+sid+"?outlet_id=out-01",
		map[string]any{"name": "Dairy Co", "category": ""}, true); code != 200 || s["name"] != "Dairy Co" || s["category"] != nil {
		t.Fatalf("patch supplier: %d %v", code, s)
	}
	if code, _ := e.do(t, "DELETE", "/api/v1/suppliers/"+sid+"?outlet_id=out-01", nil, true); code != 200 {
		t.Fatalf("delete supplier: %d", code)
	}

	// Inventory
	_, inv := e.do(t, "POST", "/api/v1/inventory?outlet_id=out-01",
		map[string]any{"name": "Milk", "unit": "L", "stock": 5, "min_stock": 2, "cost_paise": 6000}, true)
	iid := inv["id"].(string)
	if code, i := e.do(t, "PATCH", "/api/v1/inventory/"+iid+"?outlet_id=out-01",
		map[string]any{"min_stock": 0, "cost_paise": 6500}, true); code != 200 || i["min_stock"] != float64(0) || i["stock"] != float64(5) {
		t.Fatalf("patch inventory: %d %v", code, i)
	}
	if code, _ := e.do(t, "DELETE", "/api/v1/inventory/"+iid+"?outlet_id=out-01", nil, true); code != 200 {
		t.Fatalf("delete inventory: %d", code)
	}
	if code, _ := e.do(t, "POST", "/api/v1/inventory/"+iid+"/adjust?outlet_id=out-01",
		map[string]any{"delta": 1, "reason": "x"}, true); code != 404 {
		t.Fatalf("adjust deleted item: want 404, got %d", code)
	}

	// Expenses: amount edit moves the open shift's drawer.
	e.do(t, "POST", "/api/v1/shifts/open?outlet_id=out-01", map[string]any{"opening_cash_paise": 100000}, true)
	_, exp := e.do(t, "POST", "/api/v1/expenses?outlet_id=out-01",
		map[string]any{"title": "Gas", "category": "utilities", "amount_paise": 50000, "method": "cash", "vendor": "HP"}, true)
	eid := exp["id"].(string)
	code, ex := e.do(t, "PATCH", "/api/v1/expenses/"+eid+"?outlet_id=out-01",
		map[string]any{"amount_paise": 40000, "vendor": ""}, true)
	if code != 200 || ex["amount_paise"] != float64(40000) || ex["vendor"] != nil {
		t.Fatalf("patch expense: %d %v", code, ex)
	}
	_, sh := e.do(t, "GET", "/api/v1/shifts/current?outlet_id=out-01", nil, true)
	if sh["expenses_paise"] != nil && sh["expenses_paise"] != float64(40000) {
		t.Fatalf("shift expenses after edit: %v", sh["expenses_paise"])
	}
}

func TestStaffListIncludesInactive(t *testing.T) {
	e := newEnv(t)
	e.loginAs(t, "st-02", "9999")
	if code, body := e.do(t, "PATCH", "/api/v1/staff/st-04?outlet_id=out-01", map[string]any{"is_active": false}, true); code != 200 {
		t.Fatalf("deactivate: %d %v", code, body)
	}
	_, list := e.do(t, "GET", "/api/v1/staff/all?outlet_id=out-01", nil, true)
	found := false
	for _, raw := range list["staff"].([]any) {
		if s := raw.(map[string]any); s["id"] == "st-04" {
			found = s["is_active"] == false
		}
	}
	if !found {
		t.Fatalf("inactive staff missing from manager list: %v", list)
	}
	e.login(t)
	if code, _ := e.do(t, "GET", "/api/v1/staff/all?outlet_id=out-01", nil, true); code != 403 {
		t.Fatalf("cashier staff list: want 403, got %d", code)
	}
}

func TestNewOutletHasSettings(t *testing.T) {
	e := newEnv(t)
	e.loginAs(t, "st-02", "9999")
	code, st := e.do(t, "GET", "/api/v1/settings?outlet_id=out-01", nil, true)
	if code != 200 || st["gst_percent"] == nil {
		t.Fatalf("settings: %d %v", code, st)
	}
}
