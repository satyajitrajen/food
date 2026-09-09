package billing

// Gateway is the payments adapter seam. v1 ships ManualGateway (superadmin
// activates on bank/UPI receipt) and RazorpayGateway (hosted checkout +
// signature-verified webhooks). Additional gateways implement the same shape.

import (
	"context"
	"fmt"
	"time"
)

type Checkout struct {
	Gateway     string    `json:"gateway"`
	GatewayID   string    `json:"gateway_id"`
	URL         string    `json:"checkout_url,omitempty"`
	AmountPaise int64     `json:"amount_paise"`
	Currency    string    `json:"currency"`
	CreatedAt   time.Time `json:"created_at"`
}

type Gateway interface {
	Name() string
	// CreateCheckout creates a payable order. ManualGateway returns
	// ErrNotSupported — billing falls back to the superadmin flow.
	CreateCheckout(ctx context.Context, orgID string, amountPaise int64, notes string) (*Checkout, error)
	// VerifySignature authenticates a gateway webhook payload.
	VerifySignature(payload []byte, signature string) bool
}

var ErrNotSupported = fmt.Errorf("gateway does not support hosted checkout")
