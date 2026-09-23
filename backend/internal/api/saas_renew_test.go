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
	record("/v1/orders", `{"id":"order_fake1"}`)
	record("/v1/subscriptions", `{"id":"sub_fake1","status":"created"}`)
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
	// Pro plan gross = 199900 + 18% = 235882; no registration fee.
	if amt, _ := body["amount_paise"].(float64); amt != 235882 {
		t.Fatalf("gross amount = %v, want 235882", body["amount_paise"])
	}
	var subReq struct {
		Notes   map[string]string `json:"notes"`
		StartAt *int64            `json:"start_at"`
	}
	if err := json.Unmarshal([]byte(hits["/v1/subscriptions|POST"]), &subReq); err != nil {
		t.Fatal(err)
	}
	if subReq.Notes["org_id"] != orgID {
		t.Fatalf("subscription notes missing org_id: %+v", subReq)
	}
	// Fresh registration is inside the 7-day trial: the mandate must be
	// scheduled with start_at = trial end, not charged immediately.
	if body["trial"] != true {
		t.Fatalf("expected trial=true in start payload: %v", body)
	}
	subRow, err := e.st.GetSubscription(context.Background(), orgID)
	if err != nil {
		t.Fatal(err)
	}
	if subRow.TrialEndsAt == nil {
		t.Fatal("expected trial_ends_at on fresh registration")
	}
	if subReq.StartAt == nil || *subReq.StartAt != subRow.TrialEndsAt.Unix() {
		t.Fatalf("expected start_at=%d (trial end), got %+v", subRow.TrialEndsAt.Unix(), subReq.StartAt)
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

	// First charge at checkout (org still in trial): gross = plan gross.
	raw := `{"event":"subscription.charged","payload":{"payment":{"entity":{"id":"pay_first","amount":235882}},` +
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

	// Immediate cancel while the paid period still runs: no-renewal flagged,
	// access kept.
	raw = `{"event":"subscription.cancelled","payload":{"subscription":{"entity":{"id":"sub_fake1","status":"cancelled","notes":{"org_id":"` + orgID + `"}}}}}`
	if code, body := signedWebhook(t, e, cfg.RazorpayWebhookSecret, raw); code != 200 {
		t.Fatalf("cancelled webhook failed: %d %v", code, body)
	}
	sub, _ = e.st.GetSubscription(ctx, orgID)
	if sub.Status != models.SubActive || sub.GatewayStatus != "cancelled" || !sub.CancelAtPeriodEnd {
		t.Fatalf("cancel with running period must keep access + flag no-renewal, got %s / %s / %v",
			sub.Status, sub.GatewayStatus, sub.CancelAtPeriodEnd)
	}

	// Completed only records gateway state — the billing cron lapses the org
	// at period end, so a running paid period must not be cut short.
	raw = `{"event":"subscription.completed","payload":{"subscription":{"entity":{"id":"sub_fake1","status":"completed","notes":{"org_id":"` + orgID + `"}}}}}`
	if code, body := signedWebhook(t, e, cfg.RazorpayWebhookSecret, raw); code != 200 {
		t.Fatalf("completed webhook failed: %d %v", code, body)
	}
	sub, _ = e.st.GetSubscription(ctx, orgID)
	if sub.Status != models.SubActive || sub.GatewayStatus != "completed" {
		t.Fatalf("completed must not cut a running period, got %s / %s", sub.Status, sub.GatewayStatus)
	}

	// Once the period has lapsed (cron), the immediate-cancel branch applies.
	past := time.Now().Add(-time.Hour)
	next := *sub
	next.CurrentPeriodEnd = &past
	if err := e.st.UpsertSubscription(ctx, &next); err != nil {
		t.Fatal(err)
	}
	raw = `{"event":"subscription.cancelled","payload":{"subscription":{"entity":{"id":"sub_fake1","status":"cancelled","notes":{"org_id":"` + orgID + `"}}}}}`
	if code, body := signedWebhook(t, e, cfg.RazorpayWebhookSecret, raw); code != 200 {
		t.Fatalf("cancelled-after-period webhook failed: %d %v", code, body)
	}
	sub, _ = e.st.GetSubscription(ctx, orgID)
	if sub.Status != models.SubCancelled {
		t.Fatalf("expected cancelled sub after period lapsed, got %s", sub.Status)
	}
}

func TestPaymentCapturedSkipsSubscriptionPayments(t *testing.T) {
	hits := map[string]string{}
	e, cfg := newRenewEnv(t, &hits)
	registerOwner(t, e, "renew-doublefire@test")
	orgID := subOrgIDForToken(t, e)
	ctx := context.Background()

	// First subscription charge → active, one invoice.
	raw := `{"event":"subscription.charged","payload":{"payment":{"entity":{"id":"pay_first","amount":235882}},` +
		`"subscription":{"entity":{"id":"sub_fake1","status":"active","notes":{"org_id":"` + orgID + `"}}}}}`
	if code, body := signedWebhook(t, e, cfg.RazorpayWebhookSecret, raw); code != 200 {
		t.Fatalf("charged webhook failed: %d %v", code, body)
	}
	before, err := e.st.ListSaaSInvoices(ctx, orgID)
	if err != nil || len(before) != 1 {
		t.Fatalf("expected exactly 1 invoice, got %d (%v)", len(before), err)
	}

	// Razorpay also fires payment.captured for the same payment. It must be
	// ignored — subscription.charged owns subscription billing.
	raw = `{"event":"payment.captured","payload":{"payment":{"entity":{"id":"pay_first","amount":235882,` +
		`"subscription_id":"sub_fake1","notes":{"org_id":"` + orgID + `"}}}}}`
	code, body := signedWebhook(t, e, cfg.RazorpayWebhookSecret, raw)
	if code != 200 {
		t.Fatalf("captured webhook failed: %d %v", code, body)
	}
	if body["reason"] != "subscription_payment" {
		t.Fatalf("expected subscription_payment ignore reason, got %v", body)
	}
	after, _ := e.st.ListSaaSInvoices(ctx, orgID)
	if len(after) != 1 {
		t.Fatalf("payment.captured must not add an invoice, got %d", len(after))
	}

	// While auto-renew is live, a stray manual order capture is ignored too.
	raw = `{"event":"payment.captured","payload":{"payment":{"entity":{"id":"pay_manual","amount":235882,` +
		`"notes":{"org_id":"` + orgID + `"}}}}}`
	code, body = signedWebhook(t, e, cfg.RazorpayWebhookSecret, raw)
	if code != 200 || body["reason"] != "auto_renew_owns_billing" {
		t.Fatalf("expected auto_renew_owns_billing, got %d %v", code, body)
	}
	if after2, _ := e.st.ListSaaSInvoices(ctx, orgID); len(after2) != 1 {
		t.Fatalf("manual capture must not add an invoice, got %d", len(after2))
	}

	// Immediate cancel while the paid period still runs: no-renewal flagged,
	// access kept — a manual capture now just hits the already-active guard.
	raw = `{"event":"subscription.cancelled","payload":{"subscription":{"entity":{"id":"sub_fake1","status":"cancelled","notes":{"org_id":"` + orgID + `"}}}}}`
	if code, body := signedWebhook(t, e, cfg.RazorpayWebhookSecret, raw); code != 200 {
		t.Fatalf("cancelled webhook failed: %d %v", code, body)
	}
	sub, _ := e.st.GetSubscription(ctx, orgID)
	if sub.Status != models.SubActive || sub.GatewayStatus != "cancelled" || !sub.CancelAtPeriodEnd {
		t.Fatalf("cancel with running period must keep access, got %s / %s / %v",
			sub.Status, sub.GatewayStatus, sub.CancelAtPeriodEnd)
	}
	raw = `{"event":"payment.captured","payload":{"payment":{"entity":{"id":"pay_manual2","amount":235882,` +
		`"notes":{"org_id":"` + orgID + `"}}}}}`
	code, body = signedWebhook(t, e, cfg.RazorpayWebhookSecret, raw)
	if code != 200 || body["reason"] != "already_active" {
		t.Fatalf("expected already_active while paid period runs, got %d %v", code, body)
	}

	// After the billing cron lapses the period, the manual order flow can
	// activate the org again.
	past := time.Now().Add(-time.Hour)
	next := *sub
	next.CurrentPeriodEnd = &past
	if err := e.st.UpsertSubscription(ctx, &next); err != nil {
		t.Fatal(err)
	}
	raw = `{"event":"payment.captured","payload":{"payment":{"entity":{"id":"pay_manual3","amount":235882,` +
		`"notes":{"org_id":"` + orgID + `"}}}}}`
	code, body = signedWebhook(t, e, cfg.RazorpayWebhookSecret, raw)
	if code != 200 || body["activated"] != true {
		t.Fatalf("manual capture should activate after lapse, got %d %v", code, body)
	}
	sub, _ = e.st.GetSubscription(ctx, orgID)
	if sub.Status != models.SubActive {
		t.Fatalf("expected active after manual capture, got %s", sub.Status)
	}
}

func TestFirstChargeAfterTrialExpired(t *testing.T) {
	hits := map[string]string{}
	e, cfg := newRenewEnv(t, &hits)
	registerOwner(t, e, "renew-late@test")
	orgID := subOrgIDForToken(t, e)
	ctx := context.Background()

	// The cron expired the trial before the checkout payment's webhook landed.
	sub, err := e.st.GetSubscription(ctx, orgID)
	if err != nil {
		t.Fatal(err)
	}
	next := *sub
	next.Status = models.SubExpired
	if err := e.st.UpsertSubscription(ctx, &next); err != nil {
		t.Fatal(err)
	}

	// A legacy first charge may still carry the retired registration add-on in
	// its gross; the invoice must record the plan base only (structural
	// detection, not status).
	raw := `{"event":"subscription.charged","payload":{"payment":{"entity":{"id":"pay_late","amount":245982}},` +
		`"subscription":{"entity":{"id":"sub_fake1","status":"active","notes":{"org_id":"` + orgID + `"}}}}}`
	if code, body := signedWebhook(t, e, cfg.RazorpayWebhookSecret, raw); code != 200 {
		t.Fatalf("late first charge failed: %d %v", code, body)
	}
	if got := lastInvoiceBase(t, e, orgID); got != 199900 {
		t.Fatalf("late first-charge base = %d, want 199900 (add-on must not inflate the base)", got)
	}
}

func TestWebhookRejectsBadSignature(t *testing.T) {
	hits := map[string]string{}
	e, _ := newRenewEnv(t, &hits)
	req, err := http.NewRequest("POST", e.ts.URL+"/api/v1/webhooks/razorpay",
		strings.NewReader(`{"event":"payment.captured"}`))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("X-Razorpay-Signature", "deadbeef")
	res, err := e.client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("bad signature must be 401, got %d", res.StatusCode)
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

// The status read must sit outside the entitlement gate: an expired org is
// exactly when the app needs it. Staff token comes from registering an org
// (which creates an admin staff + outlet) and doing a staff PIN login.
func registerAndStaffLogin(t *testing.T, e *env, email string) (orgID string) {
	t.Helper()
	code, body := e.do(t, "POST", "/api/v1/auth/register", registerBody(email), false)
	if code != 201 {
		t.Fatalf("register failed: %d %v", code, body)
	}
	outlet, _ := body["outlet"].(map[string]any)
	outletID, _ := outlet["id"].(string)
	adminPin, _ := body["admin_pin"].(string)
	org, _ := body["org"].(map[string]any)
	orgID, _ = org["id"].(string)
	if outletID == "" || adminPin == "" || orgID == "" {
		t.Fatalf("register response incomplete: %v", body)
	}
	staffID := ""
	if err := e.st.DB.QueryRow(
		`SELECT id FROM staff WHERE org_id = ? AND role = 'admin'`, orgID).Scan(&staffID); err != nil {
		t.Fatal(err)
	}
	code, body = e.do(t, "POST", "/api/v1/auth/login", map[string]string{
		"staff_id": staffID, "pin": adminPin, "outlet_id": outletID,
	}, false)
	if code != 200 {
		t.Fatalf("staff login failed: %d %v", code, body)
	}
	token, _ := body["token"].(string)
	if token == "" {
		t.Fatalf("no staff token: %v", body)
	}
	e.token = token
	return orgID
}

func (e *env) outletIDForOrg(t *testing.T, orgID string) string {
	t.Helper()
	id := ""
	if err := e.st.DB.QueryRow(
		`SELECT id FROM outlets WHERE org_id = ? LIMIT 1`, orgID).Scan(&id); err != nil {
		t.Fatal(err)
	}
	return id
}

func TestSubscriptionAppStatusForStaff(t *testing.T) {
	hits := map[string]string{}
	e, _ := newRenewEnv(t, &hits)
	orgID := registerAndStaffLogin(t, e, "status-staff@test")

	code, body := e.do(t, "GET", "/api/v1/saas/subscription/status", nil, true)
	if code != 200 {
		t.Fatalf("status failed: %d %v", code, body)
	}
	if body["plan_code"] != "pro" || body["status"] != "trial" {
		t.Fatalf("unexpected status payload: %v", body)
	}
	if body["gateway_status"] != "" {
		t.Fatalf("expected empty gateway_status, got %v", body["gateway_status"])
	}
	if body["price_paise"] != float64(199900) {
		t.Fatalf("unexpected price: %v", body["price_paise"])
	}

	// Below-manager roles are denied the billing read.
	hash, _ := e.mgr.HashPIN("7777")
	if _, err := e.st.DB.Exec(
		`INSERT INTO staff (id, org_id, outlet_id, name, role, pin_hash, is_active)
		 VALUES ('st-status-cashier', ?, NULL, 'Cash', 'cashier', ?, 1)`, orgID, hash); err != nil {
		t.Fatal(err)
	}
	code, body = e.do(t, "POST", "/api/v1/auth/login", map[string]string{
		"staff_id": "st-status-cashier", "pin": "7777",
		"outlet_id": e.outletIDForOrg(t, orgID),
	}, false)
	if code != 200 {
		t.Fatalf("cashier login failed: %d %v", code, body)
	}
	cashierToken := body["token"].(string)
	e.token = cashierToken
	code, _ = e.do(t, "GET", "/api/v1/saas/subscription/status", nil, true)
	if code != 403 {
		t.Fatalf("cashier must be denied, got %d", code)
	}
}

// Regression for chi mount shadowing + the gate bypass: the status route lives
// at the root (static beats the /api/v1/saas owner mount's catch-all) and
// outside the entitlement gate, so an expired org — the moment the app most
// needs the card — still gets a 200, not the gate's 402.
func TestSubscriptionAppStatusReachableWhenOrgExpired(t *testing.T) {
	hits := map[string]string{}
	e, _ := newRenewEnv(t, &hits)
	orgID := registerAndStaffLogin(t, e, "status-expired@test")
	ctx := context.Background()

	// Cron-style lapse: subscription expired and org flagged expired.
	sub, err := e.st.GetSubscription(ctx, orgID)
	if err != nil {
		t.Fatal(err)
	}
	next := *sub
	next.Status = models.SubExpired
	if err := e.st.UpsertSubscription(ctx, &next); err != nil {
		t.Fatal(err)
	}
	if err := e.st.SetOrgStatus(ctx, orgID, models.OrgExpired); err != nil {
		t.Fatal(err)
	}

	code, body := e.do(t, "GET", "/api/v1/saas/subscription/status", nil, true)
	if code != 200 {
		t.Fatalf("expired org must still read its subscription status, got %d %v", code, body)
	}
	if body["status"] != models.SubExpired {
		t.Fatalf("expected expired status payload, got %v", body)
	}
}

func TestOwnerManualRenewalOrder(t *testing.T) {
	hits := map[string]string{}
	e, cfg := newRenewEnv(t, &hits)
	registerOwner(t, e, "renew-manual@test")
	orgID := subOrgIDForToken(t, e)
	ctx := context.Background()

	// One cycle at gross (pro base 199900 + 18% = 235882).
	code, body := e.do(t, "POST", "/api/v1/saas/subscription/manual-order", map[string]any{}, true)
	if code != 200 {
		t.Fatalf("manual order failed: %d %v", code, body)
	}
	if body["order_id"] != "order_fake1" {
		t.Fatalf("unexpected order id: %v", body)
	}
	if body["amount_paise"] != float64(235882) {
		t.Fatalf("unexpected amount: %v", body["amount_paise"])
	}
	if body["key_id"] != cfg.RazorpayKey {
		t.Fatalf("unexpected key id: %v", body["key_id"])
	}
	var orderReq struct {
		Notes map[string]string `json:"notes"`
	}
	if err := json.Unmarshal([]byte(hits["/v1/orders|POST"]), &orderReq); err != nil {
		t.Fatalf("bad order body: %v (%s)", err, hits["/v1/orders|POST"])
	}
	if orderReq.Notes["org_id"] != orgID {
		t.Fatalf("order notes missing org_id: %v", orderReq.Notes)
	}

	// A paid period that's still running (manual/bank-activated org, stale UI,
	// two devices) must also refuse a manual order — the webhook's
	// already-active guard would otherwise ignore the captured payment.
	sub, err := e.st.GetSubscription(ctx, orgID)
	if err != nil {
		t.Fatal(err)
	}
	future := time.Now().AddDate(0, 0, 15)
	next := *sub
	next.Status = models.SubActive
	next.CurrentPeriodEnd = &future
	if err := e.st.UpsertSubscription(ctx, &next); err != nil {
		t.Fatal(err)
	}
	code, body = e.do(t, "POST", "/api/v1/saas/subscription/manual-order", map[string]any{}, true)
	if errObj, _ := body["error"].(map[string]any); code != 409 || errObj["code"] != "already_paid" {
		t.Fatalf("expected 409 already_paid while paid period runs, got %d %v", code, body)
	}

	// While auto-renew is live the gateway owns billing — manual orders are refused.
	if err := e.st.SetOrgGatewaySubscription(ctx, orgID, "sub_fake1", "active"); err != nil {
		t.Fatal(err)
	}
	code, body = e.do(t, "POST", "/api/v1/saas/subscription/manual-order", map[string]any{}, true)
	if errObj, _ := body["error"].(map[string]any); code != 409 || errObj["code"] != "auto_renew_owns_billing" {
		t.Fatalf("expected 409 auto_renew_owns_billing while auto-renew active, got %d %v", code, body)
	}

	// Unconfigured keys → 503 (explicitly zeroed so ambient env vars can't leak in).
	emptyCfg := config.Load()
	emptyCfg.RazorpayKey, emptyCfg.RazorpaySecret = "", ""
	e2 := newEnvWithCfg(t, emptyCfg)
	registerOwner(t, e2, "renew-manual2@test")
	code, _ = e2.do(t, "POST", "/api/v1/saas/subscription/manual-order", map[string]any{}, true)
	if code != 503 {
		t.Fatalf("expected 503 unconfigured, got %d", code)
	}
}
