package api_test

// Tests for the 2026-09-13 product fixes (findings/2026-09-13-product-review.md):
// reset-token dev gate, plan catalog at registration, lead capture, and
// Razorpay failure/refund audit events.

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"foodpos/backend/internal/config"
	"foodpos/backend/internal/models"
)

func registerBody(email string) map[string]any {
	return map[string]any{
		"org_name": "Fix Test Org", "owner_name": "Owner", "email": email,
		"password": "password123", "outlet_name": "First Outlet",
	}
}

func TestForgotPasswordNeverLeaksTokenOutsideDev(t *testing.T) {
	cfg := config.Load()
	cfg.Dev = false
	cfg.SMTPHost = ""
	e := newEnvWithCfg(t, cfg)

	if code, body := e.do(t, "POST", "/api/v1/auth/register", registerBody("forgot-prod@test"), false); code != 201 {
		t.Fatalf("register failed: %d %v", code, body)
	}
	code, body := e.do(t, "POST", "/api/v1/auth/account/forgot", map[string]string{
		"email": "forgot-prod@test",
	}, false)
	if code != 503 {
		t.Fatalf("expected 503 mail_unconfigured, got %d %v", code, body)
	}
	if errObj, ok := body["error"].(map[string]any); !ok || errObj["code"] != "mail_unconfigured" {
		t.Fatalf("expected mail_unconfigured error, got %v", body)
	}
	if _, leaked := body["token"]; leaked {
		t.Fatal("token must not be echoed outside dev")
	}
}

func TestForgotPasswordEchoesTokenInDev(t *testing.T) {
	cfg := config.Load()
	cfg.Dev = true
	cfg.SMTPHost = ""
	e := newEnvWithCfg(t, cfg)

	if code, body := e.do(t, "POST", "/api/v1/auth/register", registerBody("forgot-dev@test"), false); code != 201 {
		t.Fatalf("register failed: %d %v", code, body)
	}
	code, body := e.do(t, "POST", "/api/v1/auth/account/forgot", map[string]string{
		"email": "forgot-dev@test",
	}, false)
	if code != 200 {
		t.Fatalf("expected 200 in dev, got %d %v", code, body)
	}
	if tok, _ := body["token"].(string); tok == "" {
		t.Fatalf("dev mode should echo the reset token, got %v", body)
	}
}

func TestRegisterPlanCatalog(t *testing.T) {
	e := newEnv(t)

	code, body := e.do(t, "POST", "/api/v1/auth/register", registerBody("plan-chain@test"), false)
	if code != 201 {
		t.Fatalf("register failed: %d %v", code, body)
	}
	chain, _ := body["plan"].(map[string]any)
	if chain["code"] != "pro" {
		t.Fatalf("default plan should be pro, got %v", chain["code"])
	}

	req := registerBody("plan-explicit@test")
	req["plan_code"] = "chain"
	code, body = e.do(t, "POST", "/api/v1/auth/register", req, false)
	if code != 201 {
		t.Fatalf("register chain failed: %d %v", code, body)
	}
	chain, _ = body["plan"].(map[string]any)
	if chain["code"] != "chain" {
		t.Fatalf("expected chain plan, got %v", chain["code"])
	}
	if got, _ := chain["max_outlets"].(float64); got != 100 {
		t.Fatalf("chain max_outlets = %v, want 100", chain["max_outlets"])
	}
	sub, _ := body["subscription"].(map[string]any)
	if sub["status"] != models.SubTrial {
		t.Fatalf("new org should be trial, got %v", sub["status"])
	}

	req = registerBody("plan-bad@test")
	req["plan_code"] = "platinum-plus"
	code, body = e.do(t, "POST", "/api/v1/auth/register", req, false)
	if code != 400 {
		t.Fatalf("unknown plan should 400, got %d %v", code, body)
	}
	if errObj, _ := body["error"].(map[string]any); errObj["code"] != "invalid_plan" {
		t.Fatalf("expected invalid_plan, got %v", body)
	}
}

func TestLeadCapture(t *testing.T) {
	e := newEnv(t)

	code, body := e.do(t, "POST", "/api/v1/leads", map[string]any{
		"restaurant_name": "Cafe Verify", "contact_name": "Sam", "phone": "+91 98765 43210",
		"city": "Pune", "plan_interest": "Pro Dining", "source": "landing-demo",
	}, false)
	if code != 201 {
		t.Fatalf("lead create failed: %d %v", code, body)
	}
	id, _ := body["id"].(string)
	if !strings.HasPrefix(id, "lead-") {
		t.Fatalf("expected lead- prefixed id, got %v", body)
	}

	code, body = e.do(t, "POST", "/api/v1/leads", map[string]any{
		"restaurant_name": "Cafe Verify", "phone": "123",
	}, false)
	if code != 400 {
		t.Fatalf("short phone should 400, got %d %v", code, body)
	}
	code, body = e.do(t, "POST", "/api/v1/leads", map[string]any{
		"restaurant_name": "x", "phone": "9876543210",
	}, false)
	if code != 400 {
		t.Fatalf("short name should 400, got %d %v", code, body)
	}

	// Superadmin can list leads.
	code, body = e.do(t, "POST", "/api/v1/admin/login", map[string]string{
		"email": "admin@foodpos.test", "password": "secret123",
	}, false)
	if code != 200 {
		t.Fatalf("admin login failed: %d %v", code, body)
	}
	adminToken, _ := body["token"].(string)
	e.token = adminToken
	code, body = e.do(t, "GET", "/api/v1/admin/leads", nil, true)
	if code != 200 {
		t.Fatalf("admin leads list failed: %d %v", code, body)
	}
	leads, _ := body["leads"].([]any)
	found := false
	for _, l := range leads {
		if m, ok := l.(map[string]any); ok && m["id"] == id {
			found = true
		}
	}
	if !found {
		t.Fatalf("created lead not listed: %v", body)
	}
}

func TestRazorpayFailureAndRefundAreAudited(t *testing.T) {
	cfg := config.Load()
	cfg.RazorpayWebhookSecret = "whsec_test"
	e := newEnvWithCfg(t, cfg)

	sign := func(raw string) string {
		mac := hmac.New(sha256.New, []byte("whsec_test"))
		mac.Write([]byte(raw))
		return hex.EncodeToString(mac.Sum(nil))
	}
	post := func(event string) (int, map[string]any) {
		raw := `{"event":"` + event + `","payload":{"payment":{"entity":{"id":"pay_1","amount":100000,"notes":{"org_id":"org-01"}}}}}`
		req, err := http.NewRequest("POST", e.ts.URL+"/api/v1/webhooks/razorpay", strings.NewReader(raw))
		if err != nil {
			t.Fatal(err)
		}
		req.Header.Set("X-Razorpay-Signature", sign(raw))
		res, err := e.client.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer res.Body.Close()
		var out map[string]any
		_ = json.NewDecoder(res.Body).Decode(&out)
		return res.StatusCode, out
	}

	before, err := e.st.GetSubscription(context.Background(), "org-01")
	if err != nil {
		t.Fatal(err)
	}
	for _, event := range []string{"payment.failed", "payment.refunded"} {
		code, body := post(event)
		if code != 200 {
			t.Fatalf("%s webhook failed: %d %v", event, code, body)
		}
	}
	events, err := e.st.ListOrgEvents(context.Background(), "org-01")
	if err != nil {
		t.Fatal(err)
	}
	seen := map[string]bool{}
	for _, ev := range events {
		seen[ev.Action] = true
	}
	if !seen["razorpay.payment_failed"] || !seen["razorpay.payment_refunded"] {
		t.Fatalf("expected audit events, got %v", seen)
	}
	after, err := e.st.GetSubscription(context.Background(), "org-01")
	if err != nil {
		t.Fatal(err)
	}
	if after.Status != before.Status {
		t.Fatalf("webhook must not change subscription status: %s → %s", before.Status, after.Status)
	}
}
