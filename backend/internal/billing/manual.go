package billing

import "context"

// ManualGateway records the manual (bank/UPI) flow. It cannot create hosted
// checkouts; superadmins activate orgs directly after receiving payment.
type ManualGateway struct{}

func NewManual() *ManualGateway { return &ManualGateway{} }

func (ManualGateway) Name() string { return "manual" }

func (ManualGateway) CreateCheckout(_ context.Context, orgID string, amountPaise int64, notes string) (*Checkout, error) {
	return nil, ErrNotSupported
}

func (ManualGateway) VerifySignature(_ []byte, _ string) bool { return false }
