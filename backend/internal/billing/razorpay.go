package billing

// RazorpayGateway: hosted checkout + subscriptions via the Razorpay REST API
// with HMAC-SHA256 webhook verification. Configure with
// FOODPOS_RAZORPAY_KEY_ID / _KEY_SECRET / _WEBHOOK_SECRET.

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

const defaultRazorpayBase = "https://api.razorpay.com"

type RazorpayGateway struct {
	key           string
	secret        string
	webhookSecret string
	base          string // API root, overridable for tests
	http          *http.Client
}

func NewRazorpay(key, secret, webhookSecret, baseURL string) *RazorpayGateway {
	if key == "" || secret == "" {
		return nil
	}
	return &RazorpayGateway{key: key, secret: secret, webhookSecret: webhookSecret, base: baseURL, http: &http.Client{Timeout: 10 * time.Second}}
}

func (g *RazorpayGateway) Name() string { return "razorpay" }

func (g *RazorpayGateway) endpoint(path string) string {
	if g.base == "" {
		return defaultRazorpayBase + path
	}
	return g.base + path
}

// call issues an authenticated Razorpay API request and decodes the response.
func (g *RazorpayGateway) call(ctx context.Context, method, path string, in, out any) error {
	var body io.Reader
	if in != nil {
		raw, err := json.Marshal(in)
		if err != nil {
			return err
		}
		body = bytes.NewReader(raw)
	}
	req, err := http.NewRequestWithContext(ctx, method, g.endpoint(path), body)
	if err != nil {
		return err
	}
	req.SetBasicAuth(g.key, g.secret)
	req.Header.Set("Content-Type", "application/json")
	res, err := g.http.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	if res.StatusCode >= 300 {
		return fmt.Errorf("razorpay %s %s failed (%d): %s", method, path, res.StatusCode, string(raw))
	}
	if out == nil || len(raw) == 0 {
		return nil
	}
	return json.Unmarshal(raw, out)
}

type razorpayOrderReq struct {
	Amount   int64             `json:"amount"`
	Currency string            `json:"currency"`
	Receipt  string            `json:"receipt"`
	Notes    map[string]string `json:"notes"`
}

type razorpayOrderResp struct {
	ID     string `json:"id"`
	Amount int64  `json:"amount"`
}

func (g *RazorpayGateway) CreateCheckout(ctx context.Context, orgID string, amountPaise int64, notes string) (*Checkout, error) {
	var out razorpayOrderResp
	err := g.call(ctx, http.MethodPost, "/v1/orders", razorpayOrderReq{
		Amount: amountPaise, Currency: "INR",
		Receipt: fmt.Sprintf("org-%s-%d", orgID, time.Now().Unix()),
		Notes:   map[string]string{"org_id": orgID, "notes": notes},
	}, &out)
	if err != nil {
		return nil, err
	}
	return &Checkout{
		Gateway: g.Name(), GatewayID: out.ID, AmountPaise: amountPaise,
		Currency: "INR", CreatedAt: time.Now().UTC(),
	}, nil
}

// ---- Subscriptions (auto-renew) ----

// razorpayItem is the money component shared by plans and add-ons.
type razorpayItem struct {
	Name     string `json:"name"`
	Amount   int64  `json:"amount"`
	Currency string `json:"currency"`
}

type razorpayPlanReq struct {
	Period   string       `json:"period"` // monthly | yearly
	Interval int          `json:"interval"`
	Item     razorpayItem `json:"item"`
}

type razorpayIDResp struct {
	ID string `json:"id"`
}

// CreatePlan registers a recurring plan on Razorpay and returns its id.
// Amount is the per-cycle GROSS charge (base + GST, applied by the caller).
func (g *RazorpayGateway) CreatePlan(ctx context.Context, name string, amountPaise int64, currency string, intervalDays int) (string, error) {
	period := "monthly"
	if intervalDays > 31 {
		period = "yearly"
	}
	// NOTE: Razorpay also supports period=monthly with interval=N; the seeded
	// catalog is 30/365-day only, so monthly/yearly @ interval 1 is sufficient.
	var out razorpayIDResp
	err := g.call(ctx, http.MethodPost, "/v1/plans", razorpayPlanReq{
		Period: period, Interval: 1,
		Item: razorpayItem{Name: name, Amount: amountPaise, Currency: currency},
	}, &out)
	if err != nil {
		return "", err
	}
	return out.ID, nil
}

type Subscription struct {
	ID     string `json:"id"`
	Status string `json:"status"`
}

type razorpaySubReq struct {
	PlanID         string            `json:"plan_id"`
	TotalCount     int               `json:"total_count"`
	CustomerNotify int               `json:"customer_notify"`
	Notes          map[string]string `json:"notes"`
	// StartAt schedules the first charge (Unix seconds). Used to authorize
	// the mandate during the 7-day free trial with the first debit on day 8.
	// Omitted (nil) for an immediate start.
	StartAt *int64 `json:"start_at,omitempty"`
}

// CreateSubscription creates a hosted-checkout subscription for the plan. The
// org note lets subscription.* webhooks resolve the org without a DB lookup.
// Pass startAt != nil to delay the first charge until the trial ends — the
// customer authorizes the mandate now and Razorpay debits automatically later.
func (g *RazorpayGateway) CreateSubscription(ctx context.Context, planID, orgID string, totalCount int, startAt *time.Time) (*Subscription, error) {
	var out Subscription
	var start *int64
	if startAt != nil && !startAt.IsZero() {
		unix := startAt.Unix()
		start = &unix
	}
	err := g.call(ctx, http.MethodPost, "/v1/subscriptions", razorpaySubReq{
		PlanID: planID, TotalCount: totalCount, CustomerNotify: 0,
		Notes: map[string]string{"org_id": orgID},
		StartAt: start,
	}, &out)
	if err != nil {
		return nil, err
	}
	return &out, nil
}

// CancelSubscription cancels at the end of the running cycle when atCycleEnd
// is set, else immediately. Returns the gateway-side status after the call.
func (g *RazorpayGateway) CancelSubscription(ctx context.Context, subID string, atCycleEnd bool) (string, error) {
	var out Subscription
	err := g.call(ctx, http.MethodPost, "/v1/subscriptions/"+subID+"/cancel",
		map[string]bool{"cancel_at_cycle_end": atCycleEnd}, &out)
	if err != nil {
		return "", err
	}
	return out.Status, nil
}

// VerifySignature checks the X-Razorpay-Signature header against the raw body.
func (g *RazorpayGateway) VerifySignature(payload []byte, signature string) bool {
	if g.webhookSecret == "" {
		return false
	}
	mac := hmac.New(sha256.New, []byte(g.webhookSecret))
	_, _ = mac.Write(payload)
	want := hex.EncodeToString(mac.Sum(nil))
	return hmac.Equal([]byte(want), []byte(signature))
}
