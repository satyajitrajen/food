package api

// Apple in-app subscriptions (iOS). The app buys the auto-renewable product
// with StoreKit 2 and posts the signed transaction here under the owner's
// token; that links Apple's originalTransactionId to the org (stored as
// gateway_subscription_id "apple:<id>") and opens a paid period. Renewals,
// auto-renew changes, expiry and refunds then arrive as App Store Server
// Notifications V2 on the public webhook. Both paths are idempotent per
// Apple transactionId via the saas_invoices(org_id, reference) unique index.

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"foodpos/backend/internal/billing"
	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/models"
	"foodpos/backend/internal/store"
)

func appleSubRef(originalTxID string) string { return "apple:" + originalTxID }
func appleTxRef(txID string) string          { return "apple-tx:" + txID }

// isAppleSubscription reports whether a gateway subscription id is an
// Apple one (Apple cannot be cancelled from the server).
func isAppleSubscription(gatewaySubID string) bool {
	return strings.HasPrefix(gatewaySubID, "apple:")
}

func (s *Server) appleVerifier() *billing.AppleVerifier {
	if s.AppleVerifier != nil {
		return s.AppleVerifier
	}
	return billing.NewAppleVerifier(s.Cfg.AppleBundleID)
}

// handleOwnerAppleSubscription records a StoreKit purchase or restore.
func (s *Server) handleOwnerAppleSubscription(w http.ResponseWriter, r *http.Request) {
	c, ok := claimsFrom(r)
	if !ok {
		httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
		return
	}
	var req struct {
		SignedTransaction string `json:"signed_transaction"`
	}
	if err := httpx.Decode(r, &req); err != nil || req.SignedTransaction == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "bad_request", "signed_transaction is required"))
		return
	}
	tx, err := s.appleVerifier().VerifyTransaction(req.SignedTransaction)
	if err != nil {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_transaction", "Apple transaction could not be verified"))
		return
	}
	if tx.ProductID != s.Cfg.AppleProductID {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "unknown_product", "Unknown App Store product"))
		return
	}
	if tx.RevocationDate != 0 || !tx.Expires().After(time.Now()) {
		httpx.ErrorJSON(w, r, httpx.NewError(409, "transaction_inactive", "This App Store subscription is no longer active"))
		return
	}
	// One Apple subscription pays for one org: a restore from another org's
	// Apple ID must not move or double-count it.
	ctx := r.Context()
	if owner, err := s.Store.GetOrgIDByGatewaySubscriptionID(ctx, appleSubRef(tx.OriginalTransactionID)); err == nil && owner != c.OrgID {
		httpx.ErrorJSON(w, r, httpx.NewError(409, "linked_elsewhere",
			"This App Store subscription is already linked to another organization"))
		return
	}
	renewed, err := s.applyAppleTransaction(r, c.OrgID, tx, "apple-app", "App Store purchase")
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	_ = s.Store.SetOrgGatewaySubscription(ctx, c.OrgID, appleSubRef(tx.OriginalTransactionID), "active")
	sub, err := s.Store.GetSubscriptionWithPlan(ctx, c.OrgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"renewed": renewed, "subscription": sub})
}

// applyAppleTransaction opens the paid period a transaction bought, once.
func (s *Server) applyAppleTransaction(r *http.Request, orgID string, tx *billing.AppleTransaction, actor, notes string) (bool, error) {
	ctx := r.Context()
	ref := appleTxRef(tx.TransactionID)
	if exists, err := s.Store.SaaSInvoiceExistsWithReference(ctx, orgID, ref); err == nil && exists {
		return false, nil
	}
	// Apple's India prices include GST: record the taxable base so the
	// invoice gross matches what the customer paid.
	base := int64(0)
	if gross := tx.PricePaise(); gross > 0 {
		base = int64(float64(gross)/1.18 + 0.5)
	}
	if _, _, err := s.Store.ActivateOrg(ctx, orgID, actor, "apple", 0, base, ref, notes); err != nil {
		if exists, _ := s.Store.SaaSInvoiceExistsWithReference(ctx, orgID, ref); exists {
			return false, nil
		}
		return false, err
	}
	_ = s.Store.AddOrgEvent(ctx, orgID, actor, "apple.transaction", store.MetaJSON(map[string]any{
		"transaction_id":          tx.TransactionID,
		"original_transaction_id": tx.OriginalTransactionID,
		"environment":             tx.Environment,
		"expires":                 tx.Expires(),
	}))
	return true, nil
}

// handleAppleNotification receives App Store Server Notifications V2.
func (s *Server) handleAppleNotification(w http.ResponseWriter, r *http.Request) {
	var req struct {
		SignedPayload string `json:"signedPayload"`
	}
	if err := httpx.Decode(r, &req); err != nil || req.SignedPayload == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "bad_request", "signedPayload is required"))
		return
	}
	v := s.appleVerifier()
	n, err := v.VerifyNotification(req.SignedPayload)
	if err != nil {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_notification", "Notification could not be verified"))
		return
	}
	if n.Data.SignedTransactionInfo == "" {
		// TEST and other transaction-less notifications.
		httpx.JSON(w, http.StatusOK, map[string]any{"recorded": n.NotificationType})
		return
	}
	tx, err := v.VerifyTransaction(n.Data.SignedTransactionInfo)
	if err != nil {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_transaction", "Transaction could not be verified"))
		return
	}
	ctx := r.Context()
	orgID, err := s.Store.GetOrgIDByGatewaySubscriptionID(ctx, appleSubRef(tx.OriginalTransactionID))
	if err != nil {
		// Not linked yet (the app posts the purchase itself) or a foreign
		// subscription: acknowledge so Apple does not retry forever.
		httpx.JSON(w, http.StatusOK, map[string]any{"ignored": n.NotificationType, "reason": "org_unresolved"})
		return
	}
	gw := appleSubRef(tx.OriginalTransactionID)
	switch n.NotificationType {
	case "SUBSCRIBED", "DID_RENEW":
		if tx.ProductID == s.Cfg.AppleProductID && tx.RevocationDate == 0 {
			if _, err := s.applyAppleTransaction(r, orgID, tx, "apple-webhook", "App Store renewal"); err != nil {
				httpx.ErrorJSON(w, r, err)
				return
			}
		}
		_ = s.Store.SetOrgGatewaySubscription(ctx, orgID, gw, "active")
	case "DID_CHANGE_RENEWAL_STATUS":
		on := n.Subtype == "AUTO_RENEW_ENABLED"
		status := "cancelled"
		if on {
			status = "active"
		}
		_ = s.Store.SetOrgGatewaySubscription(ctx, orgID, gw, status)
		if err := s.setCancelAtPeriodEnd(r, orgID, !on, false); err != nil {
			httpx.ErrorJSON(w, r, err)
			return
		}
	case "DID_FAIL_TO_RENEW":
		_ = s.Store.SetOrgGatewaySubscription(ctx, orgID, gw, "halted")
	case "EXPIRED", "GRACE_PERIOD_EXPIRED":
		_ = s.Store.SetOrgGatewaySubscription(ctx, orgID, gw, "completed")
		if err := s.setCancelAtPeriodEnd(r, orgID, true, false); err != nil {
			httpx.ErrorJSON(w, r, err)
			return
		}
	case "REFUND", "REVOKE":
		_ = s.Store.SetOrgGatewaySubscription(ctx, orgID, gw, "cancelled")
		if err := s.setCancelAtPeriodEnd(r, orgID, true, true); err != nil {
			httpx.ErrorJSON(w, r, err)
			return
		}
	}
	_ = s.Store.AddOrgEvent(ctx, orgID, "apple-webhook", "apple."+n.NotificationType, store.MetaJSON(map[string]any{
		"subtype":                 n.Subtype,
		"transaction_id":          tx.TransactionID,
		"original_transaction_id": tx.OriginalTransactionID,
		"environment":             n.Data.Environment,
		"notification_uuid":       n.NotificationUUID,
	}))
	httpx.JSON(w, http.StatusOK, map[string]any{"recorded": n.NotificationType})
}

// setCancelAtPeriodEnd mirrors Apple's renewal state. Like the Razorpay
// handler it never cuts a running paid period short, except on a refund or
// revocation (endNow), where the paid-for access is taken back.
func (s *Server) setCancelAtPeriodEnd(r *http.Request, orgID string, cancel, endNow bool) error {
	ctx := r.Context()
	sub, err := s.Store.GetSubscription(ctx, orgID)
	if err != nil {
		if errors.Is(err, httpx.ErrNotFound) {
			return nil
		}
		return err
	}
	next := *sub
	next.CancelAtPeriodEnd = cancel
	periodRunning := sub.CurrentPeriodEnd != nil && sub.CurrentPeriodEnd.After(time.Now())
	if cancel && (endNow || !periodRunning) {
		next.Status = models.SubCancelled
		if err := s.Store.SetOrgStatus(ctx, orgID, models.OrgExpired); err != nil {
			return err
		}
	}
	return s.Store.UpsertSubscription(ctx, &next)
}
