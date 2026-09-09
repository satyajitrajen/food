package api_test

// Integration coverage for menu admin: variants/modifier-group editing and
// photo upload + static serving + category-by-name resolution.

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"mime/multipart"
	"net/http"
	"testing"
)

// 1x1 transparent PNG used as upload fixture.
const tinyPNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

func TestMenuAdminCreateWithAddOns(t *testing.T) {
	e := newEnv(t)
	e.loginAs(t, "st-02", "9999") // manager

	// The admin UI sends the category *name*; the server must resolve it.
	code, body := e.do(t, "POST", "/api/v1/menu?outlet_id=out-01", map[string]any{
		"name":        "Loaded Fries",
		"category_id": "Starters",
		"price_paise": 19900,
		"is_veg":      true,
		"description": "Crispy fries with cheese sauce",
		"variants": []map[string]any{
			{"name": "Regular", "price_paise": 19900},
			{"name": "Large", "price_paise": 24900},
		},
		"modifier_groups": []map[string]any{
			{
				"name":            "Add-ons",
				"is_multi_select": true,
				"is_required":     false,
				"sort":            0,
				"items": []map[string]any{
					{"name": "Cheese Burst", "price_paise": 4000},
					{"name": "Jalapenos", "price_paise": 3000},
				},
			},
		},
	}, true)
	if code != 201 {
		t.Fatalf("menu create with add-ons failed: %d %v", code, body)
	}
	itemID := body["id"].(string)
	if got := len(body["variants"].([]any)); got != 2 {
		t.Fatalf("variants = %d, want 2", got)
	}
	groups := body["modifier_groups"].([]any)
	if len(groups) != 1 {
		t.Fatalf("modifier_groups = %d, want 1", len(groups))
	}
	if got := len(groups[0].(map[string]any)["items"].([]any)); got != 2 {
		t.Fatalf("modifier items = %d, want 2", got)
	}

	// PATCH with a new variant set replaces the children (partial semantics:
	// omitting the arrays would leave them untouched — here we replace).
	code, body = e.do(t, "PATCH", "/api/v1/menu/"+itemID, map[string]any{
		"variants": []map[string]any{
			{"name": "Jumbo", "price_paise": 29900},
		},
		"modifier_groups": []map[string]any{
			{
				"name":            "Toppings",
				"is_multi_select": true,
				"is_required":     true,
				"sort":            0,
				"items": []map[string]any{
					{"name": "Peri Peri", "price_paise": 2000},
				},
			},
		},
	}, true)
	if code != 200 {
		t.Fatalf("menu patch add-ons failed: %d %v", code, body)
	}
	if got := len(body["variants"].([]any)); got != 1 {
		t.Fatalf("variants after patch = %d, want 1", got)
	}
	if got := body["modifier_groups"].([]any)[0].(map[string]any)["name"]; got != "Toppings" {
		t.Fatalf("group name = %v, want Toppings", got)
	}

	// Availability-only patch (what a toggle sends) must NOT wipe add-ons.
	code, body = e.do(t, "PATCH", "/api/v1/menu/"+itemID, map[string]any{"is_available": false}, true)
	if code != 200 {
		t.Fatalf("availability patch failed: %d %v", code, body)
	}
	if got := len(body["variants"].([]any)); got != 1 {
		t.Fatalf("variants wiped by availability toggle: %d", got)
	}
}

func TestMenuPhotoUploadAndServing(t *testing.T) {
	e := newEnv(t)
	e.loginAs(t, "st-02", "9999") // manager

	png, err := base64.StdEncoding.DecodeString(tinyPNG)
	if err != nil {
		t.Fatal(err)
	}

	// Multipart upload.
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	fw, err := mw.CreateFormFile("file", "dish.png")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := fw.Write(png); err != nil {
		t.Fatal(err)
	}
	if err := mw.Close(); err != nil {
		t.Fatal(err)
	}
	req, err := http.NewRequest("POST", e.ts.URL+"/api/v1/uploads/menu-image?outlet_id=out-01", &buf)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", mw.FormDataContentType())
	req.Header.Set("Authorization", "Bearer "+e.token)
	res, err := e.client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	var up map[string]any
	if err := json.NewDecoder(res.Body).Decode(&up); err != nil {
		t.Fatal(err)
	}
	if res.StatusCode != 200 {
		t.Fatalf("upload failed: %d %v", res.StatusCode, up)
	}
	imageURL, _ := up["image_url"].(string)
	if imageURL == "" || imageURL[:11] != "/media/menu" {
		t.Fatalf("image_url = %q, want /media/menu/...", imageURL)
	}

	// The stored file is served publicly (no auth) for <img> tags.
	got, err := e.client.Get(e.ts.URL + imageURL)
	if err != nil {
		t.Fatal(err)
	}
	defer got.Body.Close()
	if got.StatusCode != 200 {
		t.Fatalf("media fetch: expected 200, got %d", got.StatusCode)
	}
	if ct := got.Header.Get("Content-Type"); ct != "image/png" {
		t.Fatalf("media content-type = %q, want image/png", ct)
	}

	// Assign the photo to an item via the normal PATCH.
	code, body := e.do(t, "PATCH", "/api/v1/menu/m-01", map[string]any{"image_url": imageURL}, true)
	if code != 200 {
		t.Fatalf("assign image failed: %d %v", code, body)
	}
	if gotURL, _ := body["image_url"].(string); gotURL != imageURL {
		t.Fatalf("item image_url = %q, want %q", gotURL, imageURL)
	}

	// Kitchen/cashier are not allowed to upload (manager/admin only).
	e.loginAs(t, "st-01", "1234") // cashier
	req, _ = http.NewRequest("POST", e.ts.URL+"/api/v1/uploads/menu-image", nil)
	req.Header.Set("Authorization", "Bearer "+e.token)
	denied, err := e.client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	denied.Body.Close()
	if denied.StatusCode != 403 {
		t.Fatalf("cashier upload: expected 403, got %d", denied.StatusCode)
	}
}
