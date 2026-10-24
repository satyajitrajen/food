package api_test

// Owner self-service account deletion (App Store guideline 5.1.1(v)).

import "testing"

func TestOwnerDeletesOrg(t *testing.T) {
	e := newEnv(t)
	org := e.register(t, "delete-me@test")

	code, body := e.do(t, "DELETE", "/api/v1/saas/org", map[string]any{"password": "wrong"}, true)
	if code != 403 {
		t.Fatalf("wrong password should 403, got %d %v", code, body)
	}

	code, body = e.do(t, "DELETE", "/api/v1/saas/org", map[string]any{"password": "secret123"}, true)
	if code != 200 || body["deleted"] != true {
		t.Fatalf("delete failed: %d %v", code, body)
	}

	// Owner can no longer sign in with the old email.
	code, _ = e.do(t, "POST", "/api/v1/auth/account/login", map[string]any{
		"email": "delete-me@test", "password": "secret123",
	}, false)
	if code == 200 {
		t.Fatal("deleted owner should not be able to log in")
	}

	// Terminals can no longer discover the org by its code.
	code, _ = e.do(t, "POST", "/api/v1/auth/device-options", map[string]any{"org_code": org.OrgCode}, false)
	if code == 200 {
		t.Fatal("deleted org code should be inactive")
	}

	// The email is free to register again.
	e.register(t, "delete-me@test")
}
