package api_test

import "testing"

// Staff can edit their own name/mobile/photo and change their own PIN, but
// not their role, and a wrong current PIN is refused.
func TestSelfProfileAndPIN(t *testing.T) {
	e := newEnv(t)
	e.login(t) // cashier st-01 / 1234

	code, me := e.do(t, "GET", "/api/v1/me", nil, true)
	if code != 200 || me["id"] != "st-01" {
		t.Fatalf("GET /me: %d %v", code, me)
	}
	origName, _ := me["name"].(string)

	code, body := e.do(t, "PATCH", "/api/v1/me", map[string]any{"name": "Rahul S", "mobile": "9820000001"}, true)
	if code != 200 || body["name"] != "Rahul S" || body["mobile"] != "9820000001" {
		t.Fatalf("PATCH /me: %d %v", code, body)
	}
	t.Cleanup(func() { e.do(t, "PATCH", "/api/v1/me", map[string]any{"name": origName}, true) })

	// Role is not self-editable: unknown field is rejected outright.
	if code, _ := e.do(t, "PATCH", "/api/v1/me", map[string]any{"role": "admin"}, true); code != 400 {
		t.Fatalf("role via /me: want 400, got %d", code)
	}
	// Avatars must be our own uploads.
	if code, _ := e.do(t, "PATCH", "/api/v1/me", map[string]any{"avatar_url": "https://evil.example/x.png"}, true); code != 400 {
		t.Fatalf("foreign avatar: want 400, got %d", code)
	}
	if code, _ := e.do(t, "PATCH", "/api/v1/me", map[string]any{"mobile": "12345"}, true); code != 400 {
		t.Fatalf("short mobile: want 400, got %d", code)
	}

	if code, body := e.do(t, "POST", "/api/v1/me/pin", map[string]string{"current_pin": "0000", "new_pin": "4321"}, true); code != 400 || body["error"].(map[string]any)["code"] != "wrong_pin" {
		t.Fatalf("wrong current PIN: %d %v", code, body)
	}
	if code, _ := e.do(t, "POST", "/api/v1/me/pin", map[string]string{"current_pin": "1234", "new_pin": "12"}, true); code != 400 {
		t.Fatalf("short new PIN: want 400, got %d", code)
	}
	if code, body := e.do(t, "POST", "/api/v1/me/pin", map[string]string{"current_pin": "1234", "new_pin": "246810"}, true); code != 200 {
		t.Fatalf("change PIN: %d %v", code, body)
	}
	e.loginAs(t, "st-01", "246810")
	// Restore for the rest of the suite.
	if code, body := e.do(t, "POST", "/api/v1/me/pin", map[string]string{"current_pin": "246810", "new_pin": "1234"}, true); code != 200 {
		t.Fatalf("restore PIN: %d %v", code, body)
	}
}
