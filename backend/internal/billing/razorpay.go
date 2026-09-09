package billing

// RazorpayGateway: hosted orders via the Razorpay Orders API + HMAC-SHA256
// webhook verification. Configure with FOODPOS_RAZORPAY_KEY_ID / _KEY_SECRET
// and FOODPOS_RAZORPAY_WEBHOOK_SECRET.

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

type RazorpayGateway struct {
	key           string
	secret        string
	webhookSecret string
	http          *http.Client
}

func NewRazorpay(key, secret, webhookSecret string) *RazorpayGateway {
	if key == "" || secret == "" {
		return nil
	}
	return &RazorpayGateway{key: key, secret: secret, webhookSecret: webhookSecret, http: &http.Client{Timeout: 10 * time.Second}}
}

func (g *RazorpayGateway) Name() string { return "razorpay" }

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
	body, _ := json.Marshal(razorpayOrderReq{
		Amount: amountPaise, Currency: "INR",
		Receipt: fmt.Sprintf("org-%s-%d", orgID, time.Now().Unix()),
		Notes:   map[string]string{"org_id": orgID, "notes": notes},
	})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://api.razorpay.com/v1/orders", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.SetBasicAuth(g.key, g.secret)
	req.Header.Set("Content-Type", "application/json")
	res, err := g.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	if res.StatusCode >= 300 {
		return nil, fmt.Errorf("razorpay order failed (%d): %s", res.StatusCode, string(raw))
	}
	var out razorpayOrderResp
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil, err
	}
	return &Checkout{
		Gateway: g.Name(), GatewayID: out.ID, AmountPaise: amountPaise,
		Currency: "INR", CreatedAt: time.Now().UTC(),
	}, nil
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
