package store

// Gateway-linkage helpers for Razorpay Subscriptions (auto-renew): the plan's
// gateway plan id, the org's hosted subscription id/status, and invoice
// idempotency keyed on the gateway payment reference.

import (
	"context"
	"database/sql"

	"foodpos/backend/internal/httpx"
)

// SetPlanGatewayID caches the gateway plan id for a billing plan.
func (s *Store) SetPlanGatewayID(ctx context.Context, planID, gatewayPlanID string) error {
	_, err := s.DB.ExecContext(ctx, `UPDATE plans SET gateway_plan_id = ? WHERE id = ?`, gatewayPlanID, planID)
	return err
}

// SetOrgGatewaySubscription links an org's subscription to the hosted gateway
// subscription and mirrors the gateway-side status.
func (s *Store) SetOrgGatewaySubscription(ctx context.Context, orgID, gatewaySubID, gatewayStatus string) error {
	_, err := s.DB.ExecContext(ctx,
		`UPDATE org_subscriptions SET gateway_subscription_id = ?, gateway_status = ?, updated_at = ? WHERE org_id = ?`,
		gatewaySubID, gatewayStatus, TimeStr(Now()), orgID)
	return err
}

// GetOrgIDByGatewaySubscriptionID resolves an org from a hosted subscription
// id — the webhook fallback when the payload carries no org note.
func (s *Store) GetOrgIDByGatewaySubscriptionID(ctx context.Context, gatewaySubID string) (string, error) {
	var orgID string
	err := s.DB.QueryRowContext(ctx,
		`SELECT org_id FROM org_subscriptions WHERE gateway_subscription_id = ?`, gatewaySubID).Scan(&orgID)
	if err == sql.ErrNoRows {
		return "", httpx.ErrNotFound
	}
	return orgID, err
}

// SaaSInvoiceExistsWithReference reports whether an invoice was already
// recorded for a gateway payment id (webhook idempotency).
func (s *Store) SaaSInvoiceExistsWithReference(ctx context.Context, orgID, reference string) (bool, error) {
	var n int
	err := s.DB.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM saas_invoices WHERE org_id = ? AND reference = ?`, orgID, reference).Scan(&n)
	return n > 0, err
}
