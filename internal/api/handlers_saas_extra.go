package api

// SaaS extras: e-mail verification & password reset, org-code rotation,
// invoice PDF downloads, Razorpay hosted checkout + webhook, and signed
// offline entitlement tokens (embedding into login payloads).

import (
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
		httpx.JSON(w, http.StatusOK, models.MailResp{Delivered: false, Token: token, Message: "SMTP disabled — dev reset token returned"})
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
	return billing.NewRazorpay(s.Cfg.RazorpayKey, s.Cfg.RazorpaySecret, s.Cfg.RazorpayWebhookSecret)
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
				ID     string            `json:"id"`
				Amount int64             `json:"amount"`
				Notes  map[string]string `json:"notes"`
			} `json:"entity"`
		} `json:"payment"`
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
	if env.Event != "payment.captured" {
		httpx.JSON(w, http.StatusOK, map[string]any{"ignored": env.Event})
		return
	}
	orgID := env.Payload.Payment.Entity.Notes["org_id"]
	if orgID == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "no_org", "Webhook payload missing org_id"))
		return
	}
	// entity.amount is gross (INR paise) — extract the taxable base (÷1.18).
	gross := env.Payload.Payment.Entity.Amount
	base := int64(float64(gross)/1.18 + 0.5)
	// Guard against duplicate webhook deliveries (idempotent activation).
	if sub, serr := s.Store.GetSubscription(r.Context(), orgID); serr == nil &&
		sub.Status == models.SubActive && sub.CurrentPeriodEnd != nil && sub.CurrentPeriodEnd.After(time.Now()) {
		httpx.JSON(w, http.StatusOK, map[string]any{"activated": false, "reason": "already_active"})
		return
	}
	// period_days 0 => ActivateOrg uses the org's plan interval.
	_, inv, err := s.Store.ActivateOrg(r.Context(), orgID, "razorpay-webhook", "razorpay",
		0, base, env.Payload.Payment.Entity.ID, "Razorpay payment captured")
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"activated": true, "invoice": inv.InvoiceNo})
}
