package api_test

// Razorpay Subscriptions (auto-renew): owner start endpoint, gateway cancel
// hookup, and the subscription.* webhook lifecycle against a fake Razorpay.

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"foodpos/backend/internal/config"
	"foodpos/backend/internal/models"
)

func signedWebhook(t *testing.T, e *env, secret, raw string) (int, map[string]any) {
	t.Helper()
	req, err := http.NewRequest("POST", e.ts.URL+"/api/v1/webhooks/razorpay", strings.NewReader(raw))
	if err != nil {
		t.Fatal(err)
	}
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(raw))
	req.Header.Set("X-Razorpay-Signature", hex.EncodeToString(mac.Sum(nil)))
	res, err := e.client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	var out map[string]any
	_ = json.NewDecoder(res.Body).Decode(&out)
	return res.StatusCode, out
}

func newRenewEnv(t *testing.T, hits *map[string]string) (*env, config.Config) {
	t.Helper()
	mux := http.NewServeMux()
	record := func(path, resp string) {
		mux.HandleFunc(path, func(w http.ResponseWriter, r *http.Request) {
			raw, _ := io.ReadAll(r.Body)
			(*hits)[path+"|"+r.Method] = string(raw)
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(resp))
		})
	}
	record("/v1/plans", `{"id":"plan_fake1"}`)
	record("/v1/subscriptions", `{"id":"sub_fake1","status":"created"}`)
	record("/v1/subscriptions/sub_fake1/addons", `{}`)
	record("/v1/subscriptions/sub_fake1/cancel", `{"id":"sub_fake1","status":"active"}`)
	ts := httptest.NewServer(mux)
	t.Cleanup(ts.Close)

	cfg := config.Load()
	cfg.RazorpayKey = "rzp_test_fake"
	cfg.RazorpaySecret = "secret_fake"
	cfg.RazorpayWebhookSecret = "whsec_test"
	cfg.RazorpayBaseURL = ts.URL
	return newEnvWithCfg(t, cfg), cfg
}

func registerOwner(t *testing.T, e *env, email string) {
	t.Helper()
	code, body := e.do(t, "POST", "/api/v1/auth/register", registerBody(email), false)
	if code != 201 {
		t.Fatalf("register failed: %d %v", code, body)
	}
	token, _ := body["token"].(string)
	if token == "" {
		t.Fatalf("no owner token: %v", body)
	}
	e.token = token
}

func TestOwnerStartSubscription(t *testing.T) {
	hits := map[string]string{}
	e, _ := newRenewEnv(t, &hits)
	registerOwner(t, e, "renew-start@test")
	orgID := subOrgIDForToken(t, e)

	code, body := e.do(t, "POST", "/api/v1/saas/subscription/razorpay", nil, true)
	if code != 200 {
		t.Fatalf("start subscription failed: %d %v", code, body)
	}
	if body["subscription_id"] != "sub_fake1" || body["key_id"] != "rzp_test_fake" {
		t.Fatalf("unexpected start payload: %v", body)
	}
	// Pro plan gross = 199900 + 18% = 235882; registration add-on 10100.
	if amt, _ := body["amount_paise"].(float64); amt != 235882 {
		t.Fatalf("gross amount = %v, want 235882", body["amount_paise"])
	}
	if reg, _ := body["registration_paise"].(float64); reg != 10100 {
		t.Fatalf("registration fee = %v, want 10100", body["registration_paise"])
	}
	if got := hits["/v1/subscriptions/sub_fake1/addons|POST"]; !strings.Contains(got, "10100") {
		t.Fatalf("registration add-on not requested: %q", got)
	}
	var subReq struct {
		Notes map[string]string `json:"notes"`
	}
	if err := json.Unmarshal([]byte(hits["/v1/subscriptions|POST"]), &subReq); err != nil {
		t.Fatal(err)
	}
	if subReq.Notes["org_id"] != orgID {
		t.Fatalf("subscription notes missing org_id: %+v", subReq)
	}

	sub, err := e.st.GetSubscription(context.Background(), orgID)
	if err != nil {
		t.Fatal(err)
	}
	if sub.GatewaySubscriptionID != "sub_fake1" || sub.GatewayStatus != "created" {
		t.Fatalf("gateway linkage not persisted: %+v", sub)
	}
	plan, err := e.st.GetPlanByID(context.Background(), sub.PlanID)
	if err != nil {
		t.Fatal(err)
	}
	if plan.GatewayPlanID != "plan_fake1" {
		t.Fatalf("gateway plan id not persisted: %+v", plan)
	}

	// Enabled + active: starting again conflicts.
	if err := e.st.SetOrgGatewaySubscription(context.Background(), orgID, "sub_fake1", "active"); err != nil {
		t.Fatal(err)
	}
	code, body = e.do(t, "POST", "/api/v1/saas/subscription/razorpay", nil, true)
	if code != 409 {
		t.Fatalf("expected 409 already_active, got %d %v", code, body)
	}
}

func TestOwnerCancelCancelsGatewayAtCycleEnd(t *testing.T) {
	hits := map[string]string{}
	e, _ := newRenewEnv(t, &hits)
	registerOwner(t, e, "renew-cancel@test")
	orgID := subOrgIDForToken(t, e)

	ctx := context.Background()
	if err := e.st.SetOrgGatewaySubscription(ctx, orgID, "sub_fake1", "active"); err != nil {
		t.Fatal(err)
	}
	code, body := e.do(t, "POST", "/api/v1/saas/subscription/cancel", nil, true)
	if code != 200 {
		t.Fatalf("cancel failed: %d %v", code, body)
	}
	if got := hits["/v1/subscriptions/sub_fake1/cancel|POST"]; got != `{"cancel_at_cycle_end":true}` {
		t.Fatalf("gateway cancel not requested at cycle end: %q", got)
	}
}

// subOrgIDForToken resolves the org id of the registered owner via /saas/me.
func subOrgIDForToken(t *testing.T, e *env) string {
	t.Helper()
	code, body := e.do(t, "GET", "/api/v1/saas/me", nil, true)
	if code != 200 {
		t.Fatalf("saas me failed: %d %v", code, body)
	}
	org, _ := body["org"].(map[string]any)
	id, _ := org["id"].(string)
	if id == "" {
		t.Fatalf("no org id in /saas/me: %v", body)
	}
	return id
}

func TestSubscriptionChargedWebhookLifecycle(t *testing.T) {
	hits := map[string]string{}
	e, cfg := newRenewEnv(t, &hits)
	registerOwner(t, e, "renew-webhook@test")
	orgID := subOrgIDForToken(t, e)
	ctx := context.Background()

	// First charge at checkout (org still in trial): gross = plan gross + 101.
	raw := `{"event":"subscription.charged","payload":{"payment":{"entity":{"id":"pay_first","amount":245982}},` +
		`"subscription":{"entity":{"id":"sub_fake1","status":"active","notes":{"org_id":"` + orgID + `"}}}}}`
	code, body := signedWebhook(t, e, cfg.RazorpayWebhookSecret, raw)
	if code != 200 {
		t.Fatalf("charged webhook failed: %d %v", code, body)
	}
	sub, err := e.st.GetSubscription(ctx, orgID)
	if err != nil {
		t.Fatal(err)
	}
	if sub.Status != models.SubActive {
		t.Fatalf("org should be active after first charge, got %s", sub.Status)
	}
	if sub.GatewayStatus != "active" || sub.GatewaySubscriptionID != "sub_fake1" {
		t.Fatalf("gateway fields not set: %+v", sub)
	}
	// Trial-branch invoice: plan base only (registration fee excluded).
	inv := lastInvoiceBase(t, e, orgID)
	if inv != 199900 {
		t.Fatalf("first invoice base = %d, want 199900", inv)
	}

	// Duplicate delivery of the same payment must not create a second invoice.
	code, body = signedWebhook(t, e, cfg.RazorpayWebhookSecret, raw)
	if code != 200 {
		t.Fatalf("duplicate webhook failed: %d %v", code, body)
	}
	if body["reason"] != "duplicate" {
		t.Fatalf("expected duplicate guard, got %v", body)
	}
	if inv2 := lastInvoiceBase(t, e, orgID); inv2 != 199900 {
		t.Fatal("duplicate payment created an extra invoice")
	}

	// Renewal charge while active: base extracted from gross (÷1.18).
	raw = `{"event":"subscription.charged","payload":{"payment":{"entity":{"id":"pay_second","amount":235882}},` +
		`"subscription":{"entity":{"id":"sub_fake1","status":"active","notes":{"org_id":"` + orgID + `"}}}}}`
	if code, body := signedWebhook(t, e, cfg.RazorpayWebhookSecret, raw); code != 200 {
		t.Fatalf("renewal webhook failed: %d %v", code, body)
	}
	if inv3 := lastInvoiceBase(t, e, orgID); inv3 != 199900 {
		t.Fatalf("renewal invoice base = %d, want 199900", inv3)
	}
	end := subscriptionPeriodEnd(t, e, orgID)
	if end.Before(time.Now().AddDate(0, 0, 29)) {
		t.Fatalf("period not extended: %v", end)
	}

	// Completed (cycle-end cancel) while active → expired.
	raw = `{"event":"subscription.completed","payload":{"subscription":{"entity":{"id":"sub_fake1","status":"completed","notes":{"org_id":"` + orgID + `"}}}}}`
	if code, body := signedWebhook(t, e, cfg.RazorpayWebhookSecret, raw); code != 200 {
		t.Fatalf("completed webhook failed: %d %v", code, body)
	}
	sub, _ = e.st.GetSubscription(ctx, orgID)
	if sub.Status != models.SubExpired {
		t.Fatalf("expected expired after completed, got %s", sub.Status)
	}

	// Immediate cancel with no running period → cancelled.
	raw = `{"event":"subscription.cancelled","payload":{"subscription":{"entity":{"id":"sub_fake1","status":"cancelled","notes":{"org_id":"` + orgID + `"}}}}}`
	if code, body := signedWebhook(t, e, cfg.RazorpayWebhookSecret, raw); code != 200 {
		t.Fatalf("cancelled webhook failed: %d %v", code, body)
	}
	sub, _ = e.st.GetSubscription(ctx, orgID)
	if sub.Status != models.SubCancelled || sub.GatewayStatus != "cancelled" {
		t.Fatalf("expected cancelled sub + gateway_status, got %s / %s", sub.Status, sub.GatewayStatus)
	}
}

func lastInvoiceBase(t *testing.T, e *env, orgID string) int64 {
	t.Helper()
	invs, err := e.st.ListSaaSInvoices(context.Background(), orgID)
	if err != nil {
		t.Fatal(err)
	}
	if len(invs) == 0 {
		t.Fatal("no invoices recorded")
	}
	return invs[0].AmountPaise // listed newest-first
}

func subscriptionPeriodEnd(t *testing.T, e *env, orgID string) time.Time {
	t.Helper()
	sub, err := e.st.GetSubscription(context.Background(), orgID)
	if err != nil {
		t.Fatal(err)
	}
	if sub.CurrentPeriodEnd == nil {
		t.Fatal("no period end set")
	}
	return *sub.CurrentPeriodEnd
}
