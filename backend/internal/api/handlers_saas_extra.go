package api

// SaaS extras: e-mail verification & password reset, org-code rotation,
// invoice PDF downloads, Razorpay hosted checkout + webhook, and signed
// offline entitlement tokens (embedding into login payloads).

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"foodpos/backend/internal/auth"
	"foodpos/backend/internal/billing"
	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/license"
	"foodpos/backend/internal/mail"
	"foodpos/backend/internal/models"
	"foodpos/backend/internal/store"
)

const accountTokenTTL = 24 * time.Hour

// signedEntitlementToken produces the HMAC entitlement string for a payload.
func (s *Server) signedEntitlementToken(e *models.Entitlement) string {
	if e == nil {
		return ""
	}
	tok, err := license.Sign(*e, s.Cfg.LicenseSecret, s.Cfg.JWTSecret)
	if err != nil {
		return ""
	}
	return tok
}

// enforceStaffLimit blocks staff creation past the plan cap.
func (s *Server) enforceStaffLimit(r *http.Request, orgID string) error {
	sub, err := s.Store.GetSubscriptionWithPlan(r.Context(), orgID)
	if err != nil {
		return err
	}
	if sub.Plan == nil {
		return nil
	}
	count, err := s.Store.CountStaff(r.Context(), orgID)
	if err != nil {
		return err
	}
	if count >= sub.Plan.MaxStaff {
		return httpx.NewError(409, "plan_limit",
			fmt.Sprintf("Plan allows at most %d staff members", sub.Plan.MaxStaff))
	}
	return nil
}

// ---- E-mail helpers (fire and forget) ----

func (s *Server) mailer() mail.Sender { return mail.New(s.Cfg) }

// ---- Forgot / reset / verify ----

func (s *Server) handleForgotPassword(w http.ResponseWriter, r *http.Request) {
	var req models.ForgotPasswordReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	req.Email = strings.ToLower(strings.TrimSpace(req.Email))
	acc, err := s.Store.GetAccountByEmail(r.Context(), req.Email)
	if err != nil {
		// Do not leak whether the account exists.
		httpx.JSON(w, http.StatusOK, models.MailResp{Delivered: false, Message: "If that account exists, a reset link was sent."})
		return
	}
	token, err := s.Store.CreateAccountToken(r.Context(), acc.ID, store.TokenReset, accountTokenTTL)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	sender := s.mailer()
	if !sender.Enabled() {
		if s.Cfg.Dev {
			httpx.JSON(w, http.StatusOK, models.MailResp{Delivered: false, Token: token, Message: "SMTP disabled — dev reset token returned"})
			return
		}
		// Never echo the token outside dev: the response would grant account
		// takeover to anyone holding an e-mail address.
		httpx.ErrorJSON(w, r, httpx.NewError(503, "mail_unconfigured",
			"Password reset is unavailable because mail is not configured on this server. Please contact support."))
		return
	}
	go func() {
		_ = sender.Send(acc.Email, "Reset your FoodPOS password", mail.Reset(acc.Name, s.Cfg.AppBaseURL, token))
	}()
	httpx.JSON(w, http.StatusOK, models.MailResp{Delivered: true, Message: "If that account exists, a reset link was sent."})
}

func (s *Server) handleResetPassword(w http.ResponseWriter, r *http.Request) {
	var req models.ResetPasswordReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if len(req.NewPassword) < 8 {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "weak_password", "Password must be at least 8 characters"))
		return
	}
	accountID, err := s.Store.ConsumeAccountToken(r.Context(), req.Token, store.TokenReset)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	hash, err := s.Auth.HashPassword(req.NewPassword)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if err := s.Store.UpdateAccountPassword(r.Context(), accountID, hash); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	_ = s.Store.RevokeAllSessions(r.Context(), auth.ScopeOwner, accountID)
	httpx.JSON(w, http.StatusOK, map[string]any{"reset": true})
}

func (s *Server) handleVerifyEmail(w http.ResponseWriter, r *http.Request) {
	var req models.VerifyEmailReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	accountID, err := s.Store.ConsumeAccountToken(r.Context(), req.Token, store.TokenVerify)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if err := s.Store.SetAccountEmailVerified(r.Context(), accountID, true); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"verified": true})
}

// ---- Org-code rotation (owner) ----

func (s *Server) handleRotateOrgCode(w http.ResponseWriter, r *http.Request) {
	c, ok := claimsFrom(r)
	if !ok {
		httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
		return
	}
	code, err := s.Store.RotateOrgCode(r.Context(), c.OrgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	_ = s.Store.AddOrgEvent(r.Context(), c.OrgID, c.ActorID, "org_code_rotated", "{}")
	httpx.JSON(w, http.StatusOK, map[string]any{"org_code": code})
}

// ---- Invoice PDFs ----

// serveInvoicePDF checks ownership then streams the generated PDF.
func (s *Server) serveInvoicePDF(w http.ResponseWriter, r *http.Request, orgID string) {
	inv, err := s.Store.GetSaaSInvoice(r.Context(), pathID(r, "id"))
	if err != nil || inv.OrgID != orgID {
		httpx.ErrorJSON(w, r, httpx.ErrNotFound)
		return
	}
	org, err := s.Store.GetOrganization(r.Context(), orgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	w.Header().Set("Content-Type", "application/pdf")
	w.Header().Set("Content-Disposition", "inline; filename="+inv.InvoiceNo+".pdf")
	if err := billing.RenderInvoicePDF(w, *org, *inv); err != nil {
		return
	}
}

func (s *Server) handleOwnerInvoicePDF(w http.ResponseWriter, r *http.Request) {
	c, ok := claimsFrom(r)
	if !ok {
		httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
		return
	}
	s.serveInvoicePDF(w, r, c.OrgID)
}

func (s *Server) handleAdminInvoicePDF(w http.ResponseWriter, r *http.Request) {
	inv, err := s.Store.GetSaaSInvoice(r.Context(), pathID(r, "id"))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	s.serveInvoicePDF(w, r, inv.OrgID)
}

// ---- Razorpay checkout (superadmin) + webhook ----

func (s *Server) razorpayGateway() *billing.RazorpayGateway {
	return billing.NewRazorpay(s.Cfg.RazorpayKey, s.Cfg.RazorpaySecret, s.Cfg.RazorpayWebhookSecret, s.Cfg.RazorpayBaseURL)
}

func (s *Server) handleAdminCheckout(w http.ResponseWriter, r *http.Request) {
	orgID := pathID(r, "id")
	gw := s.razorpayGateway()
	if gw == nil {
		httpx.ErrorJSON(w, r, httpx.NewError(503, "gateway_unconfigured", "Razorpay keys are not configured"))
		return
	}
	sub, err := s.Store.GetSubscriptionWithPlan(r.Context(), orgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	plan := sub.Plan
	if plan == nil {
		httpx.ErrorJSON(w, r, httpx.NewError(404, "no_plan", "Organization has no plan"))
		return
	}
	var req models.ActivateReq
	_ = httpx.Decode(r, &req) // body optional (notes/amount overrides)
	amount := plan.PricePaise
	if req.AmountPaise > 0 {
		amount = req.AmountPaise
	}
	// Charge the gross (base + GST) so the webhook can extract the base back.
	amount = amount + storeRound(amount)
	co, err := gw.CreateCheckout(r.Context(), orgID, amount, req.Notes)
	if err != nil {
		httpx.ErrorJSON(w, r, httpx.NewError(502, "gateway_error", err.Error()))
		return
	}
	_ = s.Store.AddOrgEvent(r.Context(), orgID, s.adminActor(r), "razorpay.order_created",
		store.MetaJSON(map[string]any{"order_id": co.GatewayID, "amount_paise": amount}))
	httpx.JSON(w, http.StatusOK, co)
}

// storeRound is 18% GST rounding shared with the store package.
func storeRound(base int64) int64 {
	return int64((float64(base)*18.0)/100.0 + 0.5)
}

type razorpayWebhookEnvelope struct {
	Event   string `json:"event"`
	Payload struct {
		Payment struct {
			Entity struct {
				ID             string            `json:"id"`
				Amount         int64             `json:"amount"`
				SubscriptionID string            `json:"subscription_id"`
				Notes          map[string]string `json:"notes"`
			} `json:"entity"`
		} `json:"payment"`
		Subscription struct {
			Entity struct {
				ID     string            `json:"id"`
				Status string            `json:"status"`
				Notes  map[string]string `json:"notes"`
			} `json:"entity"`
		} `json:"subscription"`
	} `json:"payload"`
}

func (s *Server) handleRazorpayWebhook(w http.ResponseWriter, r *http.Request) {
	gw := s.razorpayGateway()
	if gw == nil {
		httpx.ErrorJSON(w, r, httpx.NewError(503, "gateway_unconfigured", "Razorpay is not configured"))
		return
	}
	raw, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if !gw.VerifySignature(raw, r.Header.Get("X-Razorpay-Signature")) {
		httpx.ErrorJSON(w, r, httpx.NewError(401, "bad_signature", "Invalid webhook signature"))
		return
	}
	var env razorpayWebhookEnvelope
	if err := json.Unmarshal(raw, &env); err != nil {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "bad_payload", "Malformed webhook"))
		return
	}
	orgID := env.Payload.Payment.Entity.Notes["org_id"]
	switch env.Event {
	case "payment.captured":
		// Subscription charges also fire payment.captured; subscription.charged
		// owns them (the first charge's gross includes the registration add-on,
		// so its base math differs). Never account for them here.
		if env.Payload.Payment.Entity.SubscriptionID != "" {
			httpx.JSON(w, http.StatusOK, map[string]any{"ignored": env.Event, "reason": "subscription_payment"})
			return
		}
		if orgID == "" {
			httpx.ErrorJSON(w, r, httpx.NewError(400, "no_org", "Webhook payload missing org_id"))
			return
		}
		// entity.amount is gross (INR paise) — extract the taxable base (÷1.18).
		gross := env.Payload.Payment.Entity.Amount
		base := int64(float64(gross)/1.18 + 0.5)
		if sub, serr := s.Store.GetSubscription(r.Context(), orgID); serr == nil {
			// Once auto-renew is live the gateway owns billing; a stray manual
			// order capture must not double-extend on top of it.
			if sub.GatewayStatus == "active" {
				httpx.JSON(w, http.StatusOK, map[string]any{"activated": false, "reason": "auto_renew_owns_billing"})
				return
			}
			// Guard against duplicate webhook deliveries (idempotent activation).
			if sub.Status == models.SubActive && sub.CurrentPeriodEnd != nil && sub.CurrentPeriodEnd.After(time.Now()) {
				httpx.JSON(w, http.StatusOK, map[string]any{"activated": false, "reason": "already_active"})
				return
			}
		}
		// period_days 0 => ActivateOrg uses the org's plan interval.
		payID := env.Payload.Payment.Entity.ID
		_, inv, err := s.Store.ActivateOrg(r.Context(), orgID, "razorpay-webhook", "razorpay",
			0, base, payID, "Razorpay payment captured")
		if err != nil {
			// Unique-index race with a concurrent delivery of the same payment.
			if exists, _ := s.Store.SaaSInvoiceExistsWithReference(r.Context(), orgID, payID); exists {
				httpx.JSON(w, http.StatusOK, map[string]any{"activated": false, "reason": "duplicate"})
				return
			}
			httpx.ErrorJSON(w, r, err)
			return
		}
		httpx.JSON(w, http.StatusOK, map[string]any{"activated": true, "invoice": inv.InvoiceNo})
	case "payment.failed", "payment.refunded":
		// Audit only: the billing cron owns the subscription lifecycle, and a
		// single failed capture must not suspend an org on its own.
		if orgID == "" {
			httpx.JSON(w, http.StatusOK, map[string]any{"ignored": env.Event})
			return
		}
		action := "razorpay.payment_failed"
		if env.Event == "payment.refunded" {
			action = "razorpay.payment_refunded"
		}
		_ = s.Store.AddOrgEvent(r.Context(), orgID, "razorpay-webhook", action,
			store.MetaJSON(map[string]any{
				"payment_id":   env.Payload.Payment.Entity.ID,
				"amount_paise": env.Payload.Payment.Entity.Amount,
			}))
		httpx.JSON(w, http.StatusOK, map[string]any{"recorded": env.Event})
	case "subscription.charged":
		s.handleSubscriptionCharged(w, r, &env)
	case "subscription.authenticated", "subscription.activated", "subscription.pending", "subscription.halted":
		s.handleSubscriptionStatus(w, r, &env)
	case "subscription.cancelled", "subscription.completed":
		s.handleSubscriptionEnded(w, r, &env, env.Event)
	default:
		httpx.JSON(w, http.StatusOK, map[string]any{"ignored": env.Event})
	}
}

// subEntityOrg resolves the org behind a hosted subscription: the org_id note
// set at creation, falling back to the stored gateway_subscription_id.
func (s *Server) subEntityOrg(ctx context.Context, subID string, notes map[string]string) (string, error) {
	if id := notes["org_id"]; id != "" {
		return id, nil
	}
	if subID == "" {
		return "", httpx.NewError(400, "no_org", "Webhook payload missing org reference")
	}
	return s.Store.GetOrgIDByGatewaySubscriptionID(ctx, subID)
}

// handleSubscriptionCharged records the cycle payment: opens a fresh paid
// period (ActivateOrg) for the org. Idempotent per gateway payment id — the
// saas_invoices(org_id, reference) unique index backs the in-handler check,
// so concurrent/duplicate deliveries cannot double-invoice or double-extend.
func (s *Server) handleSubscriptionCharged(w http.ResponseWriter, r *http.Request, env *razorpayWebhookEnvelope) {
	ctx := r.Context()
	subEnt := env.Payload.Subscription.Entity
	orgID, err := s.subEntityOrg(ctx, subEnt.ID, subEnt.Notes)
	if err != nil {
		// Authentic event we cannot attribute (foreign deployment, deleted row):
		// a non-2xx would make Razorpay retry forever and could disable the
		// endpoint, taking ALL lifecycle updates down with it.
		httpx.JSON(w, http.StatusOK, map[string]any{"ignored": env.Event, "reason": "org_unresolved"})
		return
	}
	paymentID := env.Payload.Payment.Entity.ID
	if paymentID == "" {
		httpx.JSON(w, http.StatusOK, map[string]any{"ignored": env.Event, "reason": "no_payment_id"})
		return
	}
	if exists, err := s.Store.SaaSInvoiceExistsWithReference(ctx, orgID, paymentID); err == nil && exists {
		httpx.JSON(w, http.StatusOK, map[string]any{"renewed": false, "reason": "duplicate"})
		return
	}
	sub, err := s.Store.GetSubscription(ctx, orgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	plan, err := s.Store.GetPlanByID(ctx, sub.PlanID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	gross := env.Payload.Payment.Entity.Amount
	planGross := plan.PricePaise + storeRound(plan.PricePaise)
	// The one-time registration add-on only rides on the first cycle: when the
	// gross exceeds the plan gross, this is the first charge and the invoice
	// records the plan base only. Later cycles extract the base from the gross.
	// (Structural detection — sub status is unreliable if the trial lapsed
	// before the first charge arrived.)
	base := int64(float64(gross)/1.18 + 0.5)
	if s.Cfg.RazorpayRegistrationAmountPaise > 0 && gross > planGross {
		base = plan.PricePaise
	}
	_, inv, err := s.Store.ActivateOrg(ctx, orgID, "razorpay-webhook", "razorpay",
		0, base, paymentID, "Razorpay subscription charged")
	if err != nil {
		// Lost the unique-index race against a concurrent delivery? That is a
		// duplicate, not a failure.
		if exists, _ := s.Store.SaaSInvoiceExistsWithReference(ctx, orgID, paymentID); exists {
			httpx.JSON(w, http.StatusOK, map[string]any{"renewed": false, "reason": "duplicate"})
			return
		}
		httpx.ErrorJSON(w, r, err)
		return
	}
	_ = s.Store.SetOrgGatewaySubscription(ctx, orgID, subEnt.ID, "active")
	_ = s.Store.AddOrgEvent(ctx, orgID, "razorpay-webhook", "razorpay.subscription_charged",
		store.MetaJSON(map[string]any{
			"payment_id":         paymentID,
			"gross_amount_paise": gross,
			"gateway_sub_id":     subEnt.ID,
		}))
	httpx.JSON(w, http.StatusOK, map[string]any{"renewed": true, "invoice": inv.InvoiceNo})
}

// handleSubscriptionStatus mirrors gateway-side mandate/status transitions
// (authenticated/activated/pending/halted) onto the local subscription row.
func (s *Server) handleSubscriptionStatus(w http.ResponseWriter, r *http.Request, env *razorpayWebhookEnvelope) {
	ctx := r.Context()
	subEnt := env.Payload.Subscription.Entity
	orgID, err := s.subEntityOrg(ctx, subEnt.ID, subEnt.Notes)
	if err != nil {
		httpx.JSON(w, http.StatusOK, map[string]any{"ignored": env.Event})
		return
	}
	status := strings.TrimPrefix(env.Event, "subscription.")
	if status == "activated" {
		status = "active"
	}
	_ = s.Store.SetOrgGatewaySubscription(ctx, orgID, subEnt.ID, status)
	_ = s.Store.AddOrgEvent(ctx, orgID, "razorpay-webhook", "razorpay.subscription_"+status,
		store.MetaJSON(map[string]any{"gateway_sub_id": subEnt.ID}))
	httpx.JSON(w, http.StatusOK, map[string]any{"recorded": env.Event})
}

// handleSubscriptionEnded closes out auto-renew. Razorpay's cycle schedule
// drifts from our charge-time-based periods, so neither event cuts a still-
// running paid period short: cancelled marks no-renewal (immediately lapsing
// only when the paid period is already over), completed just records the
// gateway state and lets the billing cron lapse the org at period end.
func (s *Server) handleSubscriptionEnded(w http.ResponseWriter, r *http.Request, env *razorpayWebhookEnvelope, event string) {
	ctx := r.Context()
	subEnt := env.Payload.Subscription.Entity
	orgID, err := s.subEntityOrg(ctx, subEnt.ID, subEnt.Notes)
	if err != nil {
		httpx.JSON(w, http.StatusOK, map[string]any{"ignored": event, "reason": "org_unresolved"})
		return
	}
	gwStatus := "cancelled"
	if event == "subscription.completed" {
		gwStatus = "completed"
	}
	_ = s.Store.SetOrgGatewaySubscription(ctx, orgID, subEnt.ID, gwStatus)
	sub, err := s.Store.GetSubscription(ctx, orgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	periodRunning := sub.CurrentPeriodEnd != nil && sub.CurrentPeriodEnd.After(time.Now())
	if event == "subscription.cancelled" {
		next := *sub
		next.CancelAtPeriodEnd = true
		if !periodRunning {
			next.Status = models.SubCancelled
			if err := s.Store.SetOrgStatus(ctx, orgID, models.OrgExpired); err != nil {
				httpx.ErrorJSON(w, r, err)
				return
			}
		}
		if err := s.Store.UpsertSubscription(ctx, &next); err != nil {
			httpx.ErrorJSON(w, r, err)
			return
		}
	}
	_ = s.Store.AddOrgEvent(ctx, orgID, "razorpay-webhook", "razorpay.subscription_"+gwStatus,
		store.MetaJSON(map[string]any{"gateway_sub_id": subEnt.ID, "event": event, "period_running": periodRunning}))
	httpx.JSON(w, http.StatusOK, map[string]any{"recorded": event})
}
