package api

// Owner self-service auto-renew: creates a Razorpay hosted subscription for
// the org's current plan. The console opens checkout.js with the returned
// subscription_id + key_id; lifecycle transitions arrive via webhooks.

import (
	"net/http"
	"time"

	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/models"
	"foodpos/backend/internal/store"
)

// autoRenewLive reports whether the gateway mandate is live or mid-
// authentication — auto-renew owns billing in these states.
func autoRenewLive(gwStatus string) bool {
	switch gwStatus {
	case "active", "authenticated", "pending", "halted":
		return true
	}
	return false
}

func (s *Server) handleOwnerStartSubscription(w http.ResponseWriter, r *http.Request) {
	c, ok := claimsFrom(r)
	if !ok {
		httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
		return
	}
	gw := s.razorpayGateway()
	if gw == nil {
		httpx.ErrorJSON(w, r, httpx.NewError(503, "gateway_unconfigured", "Razorpay keys are not configured"))
		return
	}
	sub, err := s.Store.GetSubscriptionWithPlan(r.Context(), c.OrgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	plan := sub.Plan
	if plan == nil {
		httpx.ErrorJSON(w, r, httpx.NewError(404, "no_plan", "Organization has no plan"))
		return
	}
	// A live gateway mandate (checked out, retrying, or paused) means
	// auto-renew is already on — starting again would orphan the old
	// subscription on Razorpay with a live mandate against this org. A stale
	// "created" link (dismissed checkout) is fine to recreate.
	if autoRenewLive(sub.GatewayStatus) {
		httpx.ErrorJSON(w, r, httpx.NewError(409, "already_active",
			"Auto-renew is already active on this subscription"))
		return
	}

	currency := s.Cfg.RazorpayCurrency
	if currency == "" {
		currency = "INR"
	}
	// Charge the gross (base + GST) so webhook invoices can extract the base.
	gross := plan.PricePaise + storeRound(plan.PricePaise)
	planID := plan.GatewayPlanID
	if planID == "" {
		planID, err = gw.CreatePlan(r.Context(), "FoodPOS "+plan.Name, gross, currency, plan.IntervalDays)
		if err != nil {
			httpx.ErrorJSON(w, r, httpx.NewError(502, "gateway_error", err.Error()))
			return
		}
		_ = s.Store.SetPlanGatewayID(r.Context(), plan.ID, planID)
	}
	// Commitment length: 12 monthly cycles (a year) or 5 annual cycles.
	totalCount := 12
	if plan.IntervalDays > 31 {
		totalCount = 5
	}
	// Trial-aware start: when the org is still inside its 7-day free trial,
	// authorize the mandate now but schedule the first charge at trial end
	// (Razorpay start_at). Otherwise charge immediately (nil start).
	var startAt *time.Time
	trial := false
	if sub.Status == models.SubTrial && sub.TrialEndsAt != nil && sub.TrialEndsAt.After(time.Now()) {
		t := *sub.TrialEndsAt
		startAt = &t
		trial = true
	}
	rs, err := gw.CreateSubscription(r.Context(), planID, c.OrgID, totalCount, startAt)
	if err != nil {
		httpx.ErrorJSON(w, r, httpx.NewError(502, "gateway_error", err.Error()))
		return
	}
	_ = s.Store.SetOrgGatewaySubscription(r.Context(), c.OrgID, rs.ID, rs.Status)
	_ = s.Store.AddOrgEvent(r.Context(), c.OrgID, c.ActorID, "razorpay.subscription_created",
		store.MetaJSON(map[string]any{
			"gateway_sub_id": rs.ID, "plan_code": plan.Code,
			"amount_paise": gross, "total_count": totalCount,
			"trial": trial, "start_at": startAt,
		}))
	httpx.JSON(w, http.StatusOK, models.RazorpaySubscriptionStart{
		SubscriptionID: rs.ID,
		KeyID:          s.Cfg.RazorpayKey,
		PlanCode:       plan.Code,
		PlanName:       plan.Name,
		AmountPaise:    gross,
		Currency:       currency,
		Trial:          trial,
		TrialEndsAt:    sub.TrialEndsAt,
		FirstChargeAt:  startAt,
	})
}

// handleSubscriptionAppStatus backs the POS app's Settings subscription card.
// It is registered with the READS (outside the entitlement-gate group): the
// gate blocks by group membership, not HTTP method, and an expired org is
// exactly when the card is needed.
func (s *Server) handleSubscriptionAppStatus(w http.ResponseWriter, r *http.Request) {
	c, ok := claimsFrom(r)
	if !ok {
		httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
		return
	}
	sub, err := s.Store.GetSubscriptionWithPlan(r.Context(), c.OrgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	plan := sub.Plan
	if plan == nil {
		httpx.ErrorJSON(w, r, httpx.NewError(404, "no_plan", "Organization has no plan"))
		return
	}
	trialDaysLeft := 0
	var firstCharge *time.Time
	if sub.Status == models.SubTrial && sub.TrialEndsAt != nil {
		if sub.TrialEndsAt.After(time.Now()) {
			d := sub.TrialEndsAt.Sub(time.Now())
			trialDaysLeft = int(d.Hours()/24) + 1
			firstCharge = sub.TrialEndsAt
		}
	}
	httpx.JSON(w, http.StatusOK, models.SubscriptionAppStatus{
		PlanCode:      plan.Code,
		PlanName:      plan.Name,
		Status:        sub.Status,
		GatewayStatus: sub.GatewayStatus,
		PeriodEnd:     sub.CurrentPeriodEnd,
		PricePaise:    plan.PricePaise,
		TrialEndsAt:   sub.TrialEndsAt,
		TrialDaysLeft: trialDaysLeft,
		FirstChargeAt: firstCharge,
	})
}

// handleOwnerManualOrder creates a one-cycle Razorpay order for the org's
// current plan at gross (base + 18%) so the POS app can pay without the
// console. notes.org_id is set by CreateCheckout; payment.captured activates.
func (s *Server) handleOwnerManualOrder(w http.ResponseWriter, r *http.Request) {
	c, ok := claimsFrom(r)
	if !ok {
		httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
		return
	}
	gw := s.razorpayGateway()
	if gw == nil {
		httpx.ErrorJSON(w, r, httpx.NewError(503, "gateway_unconfigured", "Razorpay keys are not configured"))
		return
	}
	sub, err := s.Store.GetSubscriptionWithPlan(r.Context(), c.OrgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	plan := sub.Plan
	if plan == nil {
		httpx.ErrorJSON(w, r, httpx.NewError(404, "no_plan", "Organization has no plan"))
		return
	}
	if autoRenewLive(sub.GatewayStatus) {
		httpx.ErrorJSON(w, r, httpx.NewError(409, "auto_renew_owns_billing",
			"Auto-renew is active — cancel it before paying manually"))
		return
	}
	// A paid period that's still running means the org is already covered —
	// selling another cycle would be a captured payment the webhook ignores.
	if sub.Status == models.SubActive && sub.CurrentPeriodEnd != nil && sub.CurrentPeriodEnd.After(time.Now()) {
		httpx.ErrorJSON(w, r, httpx.NewError(409, "already_paid",
			"Subscription is already paid through "+sub.CurrentPeriodEnd.Format("2006-01-02")))
		return
	}
	gross := plan.PricePaise + storeRound(plan.PricePaise)
	co, err := gw.CreateCheckout(r.Context(), c.OrgID, gross, "manual renewal")
	if err != nil {
		httpx.ErrorJSON(w, r, httpx.NewError(502, "gateway_error", err.Error()))
		return
	}
	_ = s.Store.AddOrgEvent(r.Context(), c.OrgID, c.ActorID, "razorpay.manual_order_created",
		store.MetaJSON(map[string]any{"order_id": co.GatewayID, "amount_paise": gross}))
	httpx.JSON(w, http.StatusOK, models.RazorpayManualOrder{
		OrderID:     co.GatewayID,
		KeyID:       s.Cfg.RazorpayKey,
		AmountPaise: gross,
		Currency:    co.Currency,
		PlanName:    plan.Name,
	})
}
