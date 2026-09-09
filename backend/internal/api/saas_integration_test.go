package api_test

// SaaS end-to-end coverage: self-registration, trial entitlements, owner APIs,
// manual billing via superadmin, suspension enforcement, tenant isolation.

import (
	"testing"
)

type registeredOrg struct {
	OrgID   string
	OrgCode string
	PIN     string
	Outlet  string
}

// register creates a fresh org and stores the owner token in e.token.
func (e *env) register(t *testing.T, email string) registeredOrg {
	t.Helper()
	code, body := e.do(t, "POST", "/api/v1/auth/register", map[string]any{
		"org_name":    "Test Foods " + email,
		"owner_name":  "Test Owner",
		"email":       email,
		"password":    "secret123",
		"outlet_name": "Main Outlet",
		"terminal":    "POS-1",
	}, false)
	if code != 201 {
		t.Fatalf("register failed: %d %v", code, body)
	}
	token, _ := body["token"].(string)
	if token == "" {
		t.Fatal("no owner token returned")
	}
	e.token = token
	org := body["org"].(map[string]any)
	outlet := body["outlet"].(map[string]any)
	return registeredOrg{
		OrgID:   org["id"].(string),
		OrgCode: body["org_code"].(string),
		PIN:     body["admin_pin"].(string),
		Outlet:  outlet["id"].(string),
	}
}

// staffLoginAsAdmin logs the registered org's auto-created admin staff in.
func (e *env) staffLoginAsAdmin(t *testing.T, org registeredOrg) {
	t.Helper()
	code, body := e.do(t, "POST", "/api/v1/auth/device-options", map[string]any{
		"org_code": org.OrgCode,
	}, false)
	if code != 200 {
		t.Fatalf("device-options failed: %d %v", code, body)
	}
	staffList := body["staff"].([]any)
	var adminID string
	for _, s := range staffList {
		m := s.(map[string]any)
		if m["role"] == "admin" {
			adminID = m["id"].(string)
			break
		}
	}
	if adminID == "" {
		t.Fatal("no admin staff in device options")
	}
	code, body = e.do(t, "POST", "/api/v1/auth/login", map[string]any{
		"staff_id": adminID, "pin": org.PIN, "outlet_id": org.Outlet,
	}, false)
	if code != 200 {
		t.Fatalf("staff login failed: %d %v", code, body)
	}
	token, _ := body["token"].(string)
	e.token = token
	if ent, ok := body["entitlement"].(map[string]any); ok {
		if ent["status"] == "" {
			t.Fatal("entitlement missing status")
		}
	}
}

func TestSaaSRegistrationAndTrial(t *testing.T) {
	e := newEnv(t)
	org := e.register(t, "reg1@foodpos.test")

	// Owner sees org + trial subscription + the provisioned outlet.
	code, body := e.do(t, "GET", "/api/v1/saas/org", nil, true)
	if code != 200 {
		t.Fatalf("saas org failed: %d %v", code, body)
	}
	sub := body["subscription"].(map[string]any)
	if sub["status"] != "trial" {
		t.Fatalf("subscription status = %v, want trial", sub["status"])
	}
	outlets := body["outlets"].([]any)
	if len(outlets) != 1 {
		t.Fatalf("outlets = %d, want 1", len(outlets))
	}

	// Trial org can take orders: admin staff (PIN from registration) logs in.
	e.staffLoginAsAdmin(t, org)
	if c, _ := e.do(t, "POST", "/api/v1/orders?outlet_id="+org.Outlet,
		map[string]any{"type": "takeaway"}, true); c != 201 {
		t.Fatalf("trial order create failed: %d", c)
	}
}

func TestSuperadminManualBillingLifecycle(t *testing.T) {
	e := newEnv(t)
	org := e.register(t, "billing1@foodpos.test")

	// Superadmin login.
	code, body := e.do(t, "POST", "/api/v1/admin/login", map[string]any{
		"email": "admin@foodpos.test", "password": "secret123",
	}, false)
	if code != 200 {
		t.Fatalf("admin login failed: %d %v", code, body)
	}
	e.token = body["token"].(string)

	// Activate on receipt → invoice recorded, subscription active.
	code, body = e.do(t, "POST", "/api/v1/admin/orgs/"+org.OrgID+"/activate", map[string]any{
		"method": "bank", "notes": "NEFT ref TXN001", "period_days": 30,
	}, true)
	if code != 200 {
		t.Fatalf("activate failed: %d %v", code, body)
	}
	inv := body["invoice"].(map[string]any)
	if inv["invoice_no"] == "" {
		t.Fatal("no invoice created on activation")
	}

	// Owner sees the paid invoice and active status.
	code, body = e.do(t, "POST", "/api/v1/auth/account/login", map[string]any{
		"email": "billing1@foodpos.test", "password": "secret123",
	}, false)
	if code != 200 {
		t.Fatalf("account login failed: %d %v", code, body)
	}
	e.token = body["token"].(string)
	code, body = e.do(t, "GET", "/api/v1/saas/org", nil, true)
	if code != 200 {
		t.Fatalf("saas org failed: %d", code)
	}
	if got := body["subscription"].(map[string]any)["status"]; got != "active" {
		t.Fatalf("subscription = %v, want active after activation", got)
	}
	if invs := body["invoices"].([]any); len(invs) < 1 {
		t.Fatal("owner should see the activation invoice")
	}

	// Suspend → paid writes are blocked (402), reads still work.
	e.staffLoginAsAdmin(t, org)
	code, body = e.do(t, "POST", "/api/v1/admin/login", map[string]any{
		"email": "admin@foodpos.test", "password": "secret123",
	}, false)
	if code != 200 {
		t.Fatal("admin relogin failed")
	}
	e.token = body["token"].(string)
	code, _ = e.do(t, "POST", "/api/v1/admin/orgs/"+org.OrgID+"/suspend", map[string]any{
		"note": "unpaid",
	}, true)
	if code != 200 {
		t.Fatalf("suspend failed: %d", code)
	}
	e.staffLoginAsAdmin(t, org)
	code, _ = e.do(t, "POST", "/api/v1/orders?outlet_id="+org.Outlet,
		map[string]any{"type": "takeaway"}, true)
	if code != 402 {
		t.Fatalf("suspended org write: expected 402, got %d", code)
	}
	if c, _ := e.do(t, "GET", "/api/v1/tables?outlet_id="+org.Outlet, nil, true); c != 200 {
		t.Fatalf("suspended org read: expected 200, got %d", c)
	}
}

func TestTenantIsolation(t *testing.T) {
	e := newEnv(t)
	orgA := e.register(t, "iso-a@foodpos.test")
	_ = e.register(t, "iso-b@foodpos.test") // owner token now org B

	// Org-01 staff (st-01) cannot log into org A's outlet.
	code, _ := e.do(t, "POST", "/api/v1/auth/login", map[string]string{
		"staff_id": "st-01", "pin": "1234", "outlet_id": orgA.Outlet,
	}, false)
	if code != 403 {
		t.Fatalf("cross-org login: expected 403, got %d", code)
	}

	// Org A admin staff cannot be verified as a manager on org A via org-01's
	// manager PIN (manager pins are org-scoped now).
	e.staffLoginAsAdmin(t, orgA)
	code, body := e.do(t, "POST", "/api/v1/auth/verify-manager-pin", map[string]any{
		"pin": "9999", // org-01 manager PIN — must not be valid for org A
	}, true)
	if code != 200 {
		t.Fatalf("verify-manager-pin: expected 200 with valid=false, got %d", code)
	}
	if body["valid"] == true {
		t.Fatal("org-01 manager PIN validated inside org A — cross-tenant leak")
	}
}

func TestStaffRefreshKeepsTenant(t *testing.T) {
	e := newEnv(t)
	org := e.register(t, "refresh1@foodpos.test")
	e.staffLoginAsAdmin(t, org)
	code, body := e.do(t, "POST", "/api/v1/auth/login", map[string]any{
		"staff_id": func() string {
			code2, b2 := e.do(t, "POST", "/api/v1/auth/device-options", map[string]any{"org_code": org.OrgCode}, false)
			if code2 != 200 {
				t.Fatal("device-options failed")
			}
			for _, s := range b2["staff"].([]any) {
				if s.(map[string]any)["role"] == "admin" {
					return s.(map[string]any)["id"].(string)
				}
			}
			return ""
		}(),
		"pin": org.PIN, "outlet_id": org.Outlet,
	}, false)
	if code != 200 {
		t.Fatalf("staff login failed: %d %v", code, body)
	}
	refresh, _ := body["refresh_token"].(string)
	code, body = e.do(t, "POST", "/api/v1/auth/refresh", map[string]any{
		"refresh_token": refresh,
	}, false)
	if code != 200 {
		t.Fatalf("refresh failed: %d %v", code, body)
	}
	// No outlet param: tenant must come from the refreshed claim.
	e.token = body["token"].(string)
	if c, _ := e.do(t, "GET", "/api/v1/tables?outlet_id="+org.Outlet, nil, true); c != 200 {
		t.Fatalf("tables after refresh: expected 200, got %d", c)
	}
}
