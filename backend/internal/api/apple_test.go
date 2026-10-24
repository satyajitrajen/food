package api_test

// Apple in-app subscriptions: owner purchase endpoint and App Store Server
// Notifications V2, signed by a fake Apple chain.

import (
	"context"
	"fmt"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"foodpos/backend/internal/api"
	"foodpos/backend/internal/auth"
	"foodpos/backend/internal/billing"
	"foodpos/backend/internal/billing/appletest"
	"foodpos/backend/internal/config"
	"foodpos/backend/internal/models"
	"foodpos/backend/internal/store"
	"foodpos/backend/internal/ws"
)

const appleBundle, appleProduct = "com.nexory.hishobkr", "com.nexory.hishobkr.pro.yearly"

func newAppleEnv(t *testing.T) (*env, *appletest.Signer) {
	t.Helper()
	signer := appletest.NewSigner(t)
	cfg := config.Load()
	cfg.AppleBundleID, cfg.AppleProductID = appleBundle, appleProduct
	st := store.New(openTestDB(t))
	mgr := auth.New("test-secret", 4)
	hub := ws.NewHub()
	tickets := auth.NewTicketStore(auth.SSETicketTTL)
	hub.SetTicketStore(tickets)
	seedServer(st, mgr)
	up, err := os.MkdirTemp("", "foodpos-media-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(up) })
	srv := &api.Server{Store: st, Auth: mgr, Hub: hub, Tickets: tickets, Cfg: cfg, UploadDir: up,
		AppleVerifier: billing.NewAppleVerifierWithRoot(appleBundle, signer.Root)}
	ts := httptest.NewServer(srv.Routes())
	t.Cleanup(ts.Close)
	return &env{ts: ts, client: ts.Client(), st: st, mgr: mgr}, signer
}

func appleTx(txID, origID string, expires time.Time) map[string]any {
	return map[string]any{
		"transactionId": txID, "originalTransactionId": origID,
		"bundleId": appleBundle, "productId": appleProduct,
		"expiresDate": expires.UnixMilli(), "price": 1999000, "currency": "INR",
		"environment": "Sandbox",
	}
}

func appleNotify(t *testing.T, e *env, s *appletest.Signer, typ, subtype string, tx map[string]any) (int, map[string]any) {
	t.Helper()
	payload := s.Sign(t, map[string]any{
		"notificationType": typ, "subtype": subtype, "notificationUUID": fmt.Sprint(time.Now().UnixNano()),
		"data": map[string]any{"bundleId": appleBundle, "environment": "Sandbox",
			"signedTransactionInfo": s.Sign(t, tx)},
	})
	return e.do(t, "POST", "/api/v1/webhooks/apple", map[string]any{"signedPayload": payload}, false)
}

func TestApplePurchaseAndLifecycle(t *testing.T) {
	e, s := newAppleEnv(t)
	suffix := fmt.Sprint(time.Now().UnixNano())
	registerOwner(t, e, "apple-"+suffix+"@test")
	orgID := subOrgIDForToken(t, e)
	ctx := context.Background()
	orig := "orig-" + suffix
	year := time.Now().Add(365 * 24 * time.Hour)

	// Purchase: verified, opens a paid period, links the Apple subscription.
	buy := map[string]any{"signed_transaction": s.Sign(t, appleTx("tx1-"+suffix, orig, year))}
	if code, body := e.do(t, "POST", "/api/v1/saas/subscription/apple", buy, true); code != 200 || body["renewed"] != true {
		t.Fatalf("purchase: %d %v", code, body)
	}
	sub, err := e.st.GetSubscription(ctx, orgID)
	if err != nil {
		t.Fatal(err)
	}
	if sub.Status != models.SubActive || sub.GatewaySubscriptionID != "apple:"+orig || sub.GatewayStatus != "active" {
		t.Fatalf("not activated/linked: %+v", sub)
	}
	end1 := *sub.CurrentPeriodEnd

	// Same transaction again (restore / retry): no second period.
	if code, body := e.do(t, "POST", "/api/v1/saas/subscription/apple", buy, true); code != 200 || body["renewed"] != false {
		t.Fatalf("repeat purchase: %d %v", code, body)
	}
	// Unknown product and garbage are rejected.
	bad := appleTx("tx-bad-"+suffix, orig, year)
	bad["productId"] = "something.else"
	if code, _ := e.do(t, "POST", "/api/v1/saas/subscription/apple", map[string]any{"signed_transaction": s.Sign(t, bad)}, true); code != 400 {
		t.Fatalf("unknown product: %d", code)
	}
	if code, _ := e.do(t, "POST", "/api/v1/saas/subscription/apple", map[string]any{"signed_transaction": "x.y.z"}, true); code != 400 {
		t.Fatalf("garbage: %d", code)
	}
	// Server-side cancel is refused for Apple billing.
	if code, body := e.do(t, "POST", "/api/v1/saas/subscription/cancel", nil, true); code != 409 {
		t.Fatalf("cancel apple sub: %d %v", code, body)
	}

	// Renewal notification extends the period once.
	renew := appleTx("tx2-"+suffix, orig, year.Add(365*24*time.Hour))
	for i := 0; i < 2; i++ {
		if code, body := appleNotify(t, e, s, "DID_RENEW", "", renew); code != 200 {
			t.Fatalf("renew: %d %v", code, body)
		}
	}
	sub, _ = e.st.GetSubscription(ctx, orgID)
	if !sub.CurrentPeriodEnd.After(end1) || sub.CurrentPeriodEnd.Sub(end1) > 366*24*time.Hour {
		t.Fatalf("renewal period wrong: %v -> %v", end1, sub.CurrentPeriodEnd)
	}

	// Auto-renew off: keeps the paid period, flags cancel at period end.
	if code, _ := appleNotify(t, e, s, "DID_CHANGE_RENEWAL_STATUS", "AUTO_RENEW_DISABLED", renew); code != 200 {
		t.Fatal(code)
	}
	sub, _ = e.st.GetSubscription(ctx, orgID)
	if !sub.CancelAtPeriodEnd || sub.Status != models.SubActive || sub.GatewayStatus != "cancelled" {
		t.Fatalf("auto-renew off: %+v", sub)
	}

	// Refund: access ends now.
	if code, _ := appleNotify(t, e, s, "REFUND", "", renew); code != 200 {
		t.Fatal(code)
	}
	sub, _ = e.st.GetSubscription(ctx, orgID)
	if sub.Status != models.SubCancelled {
		t.Fatalf("refund did not end access: %+v", sub)
	}

	// Unlinked subscription notifications are acknowledged and ignored.
	if code, body := appleNotify(t, e, s, "DID_RENEW", "", appleTx("tx9-"+suffix, "nobody-"+suffix, year)); code != 200 || body["ignored"] == nil {
		t.Fatalf("unlinked: %d %v", code, body)
	}

	// Another org cannot claim the same Apple subscription.
	registerOwner(t, e, "apple2-"+suffix+"@test")
	steal := map[string]any{"signed_transaction": s.Sign(t, appleTx("tx3-"+suffix, orig, year))}
	if code, _ := e.do(t, "POST", "/api/v1/saas/subscription/apple", steal, true); code != 409 {
		t.Fatalf("cross-org claim: %d", code)
	}
}
