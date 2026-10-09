package api_test

// Replaces the old Green Candle seed test (which read /root/… and wrote
// through a demo outlet): cmd/admin import-menu's store path against a fresh
// outlet, verified through the public menu API.

import (
	"context"
	"os"
	"testing"

	"foodpos/backend/internal/menuimport"
)

func TestMenuImportUpsert(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	if _, err := e.st.DB.Exec(`INSERT INTO outlets (id, org_id, name, terminal) VALUES ('out-import', 'org-01', 'Import Test', 'POS-9')
		ON CONFLICT (id) DO NOTHING`); err != nil {
		t.Fatal(err)
	}
	f, err := os.Open("../menuimport/testdata/menu_sample.csv")
	if err != nil {
		t.Fatal(err)
	}
	items, err := menuimport.Parse(f)
	f.Close()
	if err != nil {
		t.Fatal(err)
	}

	res, err := e.st.ImportMenu(ctx, "out-import", items, false)
	if err != nil {
		t.Fatalf("import: %v", err)
	}
	if res.Created != len(items) || res.Updated != 0 {
		t.Fatalf("first import = %+v, want %d created", res, len(items))
	}
	first, _ := e.st.ListMenu(ctx, "out-import", "")
	ids := map[string]string{}
	for _, m := range first {
		ids[m.Name] = m.ID
	}

	// Re-import is an upsert: same ids, nothing duplicated.
	res, err = e.st.ImportMenu(ctx, "out-import", items, false)
	if err != nil {
		t.Fatalf("re-import: %v", err)
	}
	if res.Created != 0 || res.Updated != len(items) {
		t.Fatalf("re-import = %+v, want %d updated", res, len(items))
	}

	// --replace with a subset soft-deletes the rest.
	res, err = e.st.ImportMenu(ctx, "out-import", items[:2], true)
	if err != nil {
		t.Fatalf("replace import: %v", err)
	}
	if res.Removed != int64(len(items)-2) {
		t.Fatalf("replace removed %d, want %d", res.Removed, len(items)-2)
	}

	// Log in to the outlet and read it back through the API.
	code, body := e.do(t, "POST", "/api/v1/auth/login", map[string]string{
		"staff_id": "st-02", "pin": "9999", "outlet_id": "out-import",
	}, false)
	if code != 200 {
		t.Fatalf("login: %d %v", code, body)
	}
	e.token = body["token"].(string)
	code, body = e.do(t, "GET", "/api/v1/menu", nil, true)
	if code != 200 {
		t.Fatalf("menu: %d %v", code, body)
	}
	list := body["menu_items"].([]any)
	if len(list) != 2 {
		t.Fatalf("live menu has %d items, want 2", len(list))
	}
	m := list[0].(map[string]any)
	for _, raw := range list {
		if it := raw.(map[string]any); it["name"] == "Special Arakha Masoor" {
			m = it
		}
	}
	if m["id"] != ids["Special Arakha Masoor"] {
		t.Fatalf("upsert changed the item id: %v vs %v", m["id"], ids["Special Arakha Masoor"])
	}
	if int64(m["price_paise"].(float64)) != 10000 {
		t.Fatalf("base price = %v, want Full 10000", m["price_paise"])
	}
	vars := m["variants"].([]any)
	if len(vars) != 2 || vars[0].(map[string]any)["name"] != "Half" {
		t.Fatalf("variants = %v", vars)
	}
}
