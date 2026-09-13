package api

// Owner self-service auto-renew: creates a Razorpay hosted subscription for
// the org's current plan. The console opens checkout.js with the returned
// subscription_id + key_id; lifecycle transitions arrive via webhooks.

import (
	"net/http"

	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/models"
	"foodpos/backend/internal/store"
)

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
	switch sub.GatewayStatus {
	case "active", "authenticated", "pending", "halted":
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
	rs, err := gw.CreateSubscription(r.Context(), planID, c.OrgID, totalCount)
	if err != nil {
		httpx.ErrorJSON(w, r, httpx.NewError(502, "gateway_error", err.Error()))
		return
	}
	// One-time registration fee rides along with the first cycle.
	regPaise := s.Cfg.RazorpayRegistrationAmountPaise
	if regPaise > 0 {
		if err := gw.CreateSubscriptionAddon(r.Context(), rs.ID, "FoodPOS registration fee", regPaise, currency); err != nil {
			_ = s.Store.AddOrgEvent(r.Context(), c.OrgID, c.ActorID, "razorpay.addon_failed",
				store.MetaJSON(map[string]any{"error": err.Error(), "gateway_sub_id": rs.ID}))
		}
	}
	_ = s.Store.SetOrgGatewaySubscription(r.Context(), c.OrgID, rs.ID, rs.Status)
	_ = s.Store.AddOrgEvent(r.Context(), c.OrgID, c.ActorID, "razorpay.subscription_created",
		store.MetaJSON(map[string]any{
			"gateway_sub_id": rs.ID, "plan_code": plan.Code,
			"amount_paise": gross, "registration_paise": regPaise, "total_count": totalCount,
		}))
	httpx.JSON(w, http.StatusOK, models.RazorpaySubscriptionStart{
		SubscriptionID:    rs.ID,
		KeyID:             s.Cfg.RazorpayKey,
		PlanCode:          plan.Code,
		PlanName:          plan.Name,
		AmountPaise:       gross,
		Currency:          currency,
		RegistrationPaise: regPaise,
	})
}
