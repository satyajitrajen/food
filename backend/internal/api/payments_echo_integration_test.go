package api_test

import "testing"

// Split payments must echo their tender legs on the single-order GET so the
// receipt can print one Paid row per leg; the scalar payment_method stays
// 'split' for old clients.
func TestSplitPaymentEcho(t *testing.T) {
	e := newEnv(t)
	e.login(t)

	code, body := e.do(t, "POST", "/api/v1/orders?outlet_id=out-01", map[string]any{
		"type": "dine_in", "table_id": "t-02", "guest_count": 2,
	}, true)
	if code != 201 {
		t.Fatalf("order create failed: %d %v", code, body)
	}
	orderID, _ := body["id"].(string)

	code, body = e.do(t, "POST", "/api/v1/orders/"+orderID+"/items", map[string]any{
		"menu_item_id": "m-01", "quantity": 1,
	}, true)
	if code != 201 {
		t.Fatalf("add item failed: %d %v", code, body)
	}
	// Other tests mutate out-01's tax settings, so don't hardcode the total —
	// only require room for a cash leg of 20000.
	total := int64(body["grand_total_paise"].(float64))
	if total <= 20000 {
		t.Fatalf("grand total = %d, too small to split", total)
	}

	// Leave the outlet shiftless before opening our own.
	e.do(t, "POST", "/api/v1/shifts/current/close?outlet_id=out-01", map[string]any{
		"counted_paise": 0,
	}, true)
	if code, body := e.do(t, "POST", "/api/v1/shifts/open?outlet_id=out-01", map[string]any{
		"opening_paise": 0,
	}, true); code != 201 {
		t.Fatalf("shift open failed: %d %v", code, body)
	}

	code, body = e.do(t, "POST", "/api/v1/orders/"+orderID+"/pay", map[string]any{
		"amount_received_paise": total,
		"splits": []map[string]any{
			{"method": "cash", "amount_paise": 20000},
			{"method": "upi", "amount_paise": total - 20000},
		},
	}, true)
	if code != 200 {
		t.Fatalf("split pay failed: %d %v", code, body)
	}
	if body["payment_method"] != "split" {
		t.Fatalf("payment_method = %v, want split", body["payment_method"])
	}

	code, body = e.do(t, "GET", "/api/v1/orders/"+orderID, nil, true)
	if code != 200 {
		t.Fatalf("get order failed: %d", code)
	}
	payments, ok := body["payments"].([]any)
	if !ok || len(payments) != 2 {
		t.Fatalf("expected 2 payment legs in order echo, got %v", body["payments"])
	}
	var cashAmt, upiAmt int64
	for _, p := range payments {
		leg := p.(map[string]any)
		amt := int64(leg["amount_paise"].(float64))
		switch leg["method"] {
		case "cash":
			cashAmt = amt
		case "upi":
			upiAmt = amt
		}
	}
	if cashAmt != 20000 {
		t.Fatalf("cash leg = %d, want 20000 (%v)", cashAmt, payments)
	}
	if upiAmt != total-20000 {
		t.Fatalf("upi leg = %d, want %d (%v)", upiAmt, total-20000, payments)
	}

	// Leave the outlet shiftless for later tests.
	if code, body := e.do(t, "POST", "/api/v1/shifts/current/close?outlet_id=out-01", map[string]any{
		"counted_paise": 0,
	}, true); code != 200 {
		t.Fatalf("close shift failed: %d %v", code, body)
	}
}
