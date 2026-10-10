package api_test

import "testing"

// Managers can rename/resize and remove tables; a table with a running order
// can't be removed, a removed number can be reused, and other roles can't
// change the layout.
func TestTableEditAndDelete(t *testing.T) {
	e := newEnv(t)
	e.loginAs(t, "st-02", "9999") // manager

	code, body := e.do(t, "POST", "/api/v1/tables?outlet_id=out-01",
		map[string]any{"table_number": "TX1", "seats": 4, "floor": "Garden", "status": "available"}, true)
	if code != 201 && code != 200 {
		t.Fatalf("create table: %d %v", code, body)
	}
	id, _ := body["id"].(string)

	code, body = e.do(t, "PATCH", "/api/v1/tables/"+id+"?outlet_id=out-01",
		map[string]any{"table_number": "TX2", "seats": 6}, true)
	if code != 200 || body["table_number"] != "TX2" || body["seats"] != float64(6) {
		t.Fatalf("edit table: %d %v", code, body)
	}
	if code, _ := e.do(t, "PATCH", "/api/v1/tables/"+id+"?outlet_id=out-01",
		map[string]any{"table_number": "T01"}, true); code != 409 {
		t.Fatalf("duplicate number: want 409, got %d", code)
	}
	if code, _ := e.do(t, "PATCH", "/api/v1/tables/"+id+"?outlet_id=out-01",
		map[string]any{"seats": 0}, true); code != 400 {
		t.Fatalf("zero seats: want 400, got %d", code)
	}

	// Cashiers may change status but not the layout.
	e.login(t) // cashier st-01
	if code, _ := e.do(t, "PATCH", "/api/v1/tables/"+id+"?outlet_id=out-01",
		map[string]any{"seats": 8}, true); code != 403 {
		t.Fatalf("cashier layout edit: want 403, got %d", code)
	}
	if code, _ := e.do(t, "PATCH", "/api/v1/tables/"+id+"?outlet_id=out-01",
		map[string]any{"status": "reserved"}, true); code != 200 {
		t.Fatalf("cashier status change: want 200, got %d", code)
	}
	if code, _ := e.do(t, "DELETE", "/api/v1/tables/"+id+"?outlet_id=out-01", nil, true); code != 403 {
		t.Fatalf("cashier delete: want 403, got %d", code)
	}

	e.loginAs(t, "st-02", "9999")
	if code, body := e.do(t, "DELETE", "/api/v1/tables/"+id+"?outlet_id=out-01", nil, true); code != 200 {
		t.Fatalf("delete table: %d %v", code, body)
	}
	_, list := e.do(t, "GET", "/api/v1/tables?outlet_id=out-01", nil, true)
	for _, raw := range list["tables"].([]any) {
		if raw.(map[string]any)["id"] == id {
			t.Fatalf("deleted table still listed")
		}
	}
	// The number is free again.
	code, body = e.do(t, "POST", "/api/v1/tables?outlet_id=out-01",
		map[string]any{"table_number": "TX2", "seats": 2, "floor": "Garden", "status": "available"}, true)
	if code != 201 && code != 200 {
		t.Fatalf("reuse number: %d %v", code, body)
	}
	busyID, _ := body["id"].(string)

	// A table with a running order can't be removed.
	if code, body := e.do(t, "POST", "/api/v1/orders?outlet_id=out-01",
		map[string]any{"type": "dine_in", "table_id": busyID}, true); code != 201 {
		t.Fatalf("order on table: %d %v", code, body)
	}
	if code, body := e.do(t, "DELETE", "/api/v1/tables/"+busyID+"?outlet_id=out-01", nil, true); code != 409 {
		t.Fatalf("delete busy table: want 409, got %d %v", code, body)
	}
}
