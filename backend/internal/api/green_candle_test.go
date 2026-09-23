package api_test

import (
	"encoding/json"
	"os"
	"testing"
)

func TestGreenCandleMenuImport(t *testing.T) {
	e := newEnv(t)
	// Create Green Candle outlet first (manager can then login to it)
	_, err := e.st.DB.Exec(`INSERT INTO outlets (id, org_id, name, address, terminal, gstin, fssai, phone, is_online) VALUES ('out-green-candle','org-01','Hotel Green Candle','Main Road','POS-GC-01','27AAAAA0000A1Z5','11521000000125','+91 98765 43212',1) ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name`)
	if err != nil {
		t.Fatalf("outlet create: %v", err)
	}
	// Clean previous GC menu for idempotency (allows re-running test)
	_, _ = e.st.DB.Exec(`DELETE FROM menu_items WHERE outlet_id='out-green-candle'`)
	_, _ = e.st.DB.Exec(`DELETE FROM menu_categories WHERE outlet_id='out-green-candle' AND name IN ('अरख्खा मसूर स्पेशल','दाल फ्राय स्पेशल','इंडियन व्हेज स्पेशल','काजू स्पेशल','व्हेज स्पेशल','राईस स्पेशल','रोटी स्पेशल','थंडाई स्पेशल','पापड स्पेशल')`)
	// Login as manager to the Green Candle outlet (org-wide manager can access any outlet in org-01)
	code0, body0 := e.do(t, "POST", "/api/v1/auth/login", map[string]string{"staff_id": "st-02", "pin": "9999", "outlet_id": "out-green-candle"}, false)
	if code0 != 200 {
		t.Fatalf("login to green-candle failed: %d %v", code0, body0)
	}
	if tok, _ := body0["token"].(string); tok != "" {
		e.token = tok
	} else {
		t.Fatalf("no token in login: %v", body0)
	}
	// load JSON
	raw, err := os.ReadFile("/root/food/assets/green_candle_menu.json")
	if err != nil {
		t.Fatalf("read json: %v", err)
	}
	var items []map[string]any
	if err := json.Unmarshal(raw, &items); err != nil {
		t.Fatalf("json: %v", err)
	}
	// Insert each via API POST /api/v1/menu?outlet_id=out-green-candle
	for _, it := range items {
		payload := map[string]any{
			"category_id":   it["category_id"],
			"name":          it["name"],
			"description":   it["description"],
			"price_paise":   it["price_paise"],
			"is_veg":        it["is_veg"],
			"is_bestseller": it["is_bestseller"],
			"image_url":     it["image_url"],
		}
		if v, ok := it["variants"]; ok {
			payload["variants"] = v
		}
		code, body := e.do(t, "POST", "/api/v1/menu?outlet_id=out-green-candle", payload, true)
		if code != 201 {
			t.Fatalf("menu create %s failed: %d %v", it["name"], code, body)
		}
	}

	// List and verify
	code, body := e.do(t, "GET", "/api/v1/menu?outlet_id=out-green-candle", nil, true)
	if code != 200 {
		t.Fatalf("list failed: %d %v", code, body)
	}
	list, ok := body["menu_items"].([]any)
	if !ok {
		t.Fatalf("no menu_items field: %v", body)
	}
	if len(list) != 57 {
		t.Fatalf("menu count = %d, want 57, body %v", len(list), len(body))
	}
	// Verify a variant item
	foundGC01 := false
	foundGC20 := false
	for _, raw := range list {
		m := raw.(map[string]any)
		if m["name"] == "स्पेशल अरख्खा मसूर" {
			foundGC01 = true
			vars, _ := m["variants"].([]any)
			if len(vars) != 2 {
				t.Fatalf("gc-01 variants = %d, want 2", len(vars))
			}
			prices := map[float64]bool{}
			for _, vv := range vars {
				vm := vv.(map[string]any)
				prices[vm["price_paise"].(float64)] = true
			}
			if !prices[6000] || !prices[10000] {
				t.Fatalf("gc-01 variant prices mismatch: %v", prices)
			}
		}
		if m["name"] == "ग्रीन कँडल स्पेशल" {
			foundGC20 = true
			if m["is_bestseller"] != true {
				t.Fatalf("gc-20 not bestseller: %v", m)
			}
			if int(m["price_paise"].(float64)) != 29900 {
				t.Fatalf("gc-20 price %v want 29900", m["price_paise"])
			}
		}
		if m["name"] == "प्लेन राईस" {
			vars, _ := m["variants"].([]any)
			if len(vars) != 2 {
				t.Fatalf("plain rice variants %d want 2", len(vars))
			}
		}
		if m["name"] == "गव्हाची रोटी" {
			vars, _ := m["variants"].([]any)
			if len(vars) != 2 {
				t.Fatalf("ghavachi roti variants %d want 2", len(vars))
			}
		}
	}
	if !foundGC01 {
		t.Fatalf("gc-01 not found")
	}
	if !foundGC20 {
		t.Fatalf("gc-20 not found")
	}

	// Outlet isolation: list for out-01 should not contain GC items (need session for out-01)
	code1, body1 := e.do(t, "POST", "/api/v1/auth/login", map[string]string{"staff_id": "st-02", "pin": "9999", "outlet_id": "out-01"}, false)
	if code1 != 200 {
		t.Fatalf("login to out-01 failed: %d %v", code1, body1)
	}
	if tok, _ := body1["token"].(string); tok != "" {
		e.token = tok
	}
	code, body = e.do(t, "GET", "/api/v1/menu?outlet_id=out-01", nil, true)
	if code != 200 {
		t.Fatalf("list out-01 failed: %d %v", code, body)
	}
	list01, _ := body["menu_items"].([]any)
	for _, raw := range list01 {
		m := raw.(map[string]any)
		if m["name"] == "स्पेशल अरख्खा मसूर" {
			t.Fatalf("out-01 leaked GC item")
		}
	}
	// Switch back to Green Candle for remaining checks
	code1, body1 = e.do(t, "POST", "/api/v1/auth/login", map[string]string{"staff_id": "st-02", "pin": "9999", "outlet_id": "out-green-candle"}, false)
	if code1 != 200 {
		t.Fatalf("re-login to green-candle failed: %d", code1)
	}
	if tok, _ := body1["token"].(string); tok != "" {
		e.token = tok
	}
	code, body = e.do(t, "GET", "/api/v1/menu?outlet_id=out-green-candle", nil, true)
	if code != 200 {
		t.Fatalf("customer menu check failed: %d", code)
	}
	if lv, ok := body["menu_items"].([]any); ok {
		list = lv
	}

	rows, err := e.st.DB.Query(`SELECT name FROM menu_categories WHERE outlet_id='out-green-candle'`)
	if err != nil {
		t.Fatalf("category query: %v", err)
	}
	defer rows.Close()
	count := 0
	cats := map[string]bool{}
	for rows.Next() {
		var name string
		rows.Scan(&name)
		cats[name] = true
		count++
	}
	if count != 9 {
		t.Fatalf("GC categories = %d, want 9, got %v", count, cats)
	}
	for _, exp := range []string{"अरख्खा मसूर स्पेशल", "दाल फ्राय स्पेशल", "इंडियन व्हेज स्पेशल", "काजू स्पेशल", "व्हेज स्पेशल", "राईस स्पेशल", "रोटी स्पेशल", "थंडाई स्पेशल", "पापड स्पेशल"} {
		if !cats[exp] {
			t.Fatalf("missing category %q", exp)
		}
	}

	for _, raw := range list {
		m := raw.(map[string]any)
		if m["name"] == "गव्हाची रोटी" {
			vars, _ := m["variants"].([]any)
			for _, vv := range vars {
				vm := vv.(map[string]any)
				if vm["name"] == "साधी" && int(vm["price_paise"].(float64)) != 2000 {
					t.Fatalf("ghavachi sadhi price %v want 2000", vm["price_paise"])
				}
				if vm["name"] == "बटर" && int(vm["price_paise"].(float64)) != 2500 {
					t.Fatalf("ghavachi butter price %v want 2500", vm["price_paise"])
				}
			}
		}
	}
}
