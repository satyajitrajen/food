package store

// Subscription state-machine operations shared by the superadmin API, the
// cmd/admin CLI and the daily billing job. Manual billing: an activation
// records a paid SaaS invoice and opens a new period.

import (
	"context"
	"math"
	"time"

	"foodpos/backend/internal/models"
)

// SaaSGSTPercent is the GST rate applied to SaaS invoices (software services).
const SaaSGSTPercent = 18.0

func roundPaise(v float64) int64 { return int64(math.Round(v)) }

// ActivateOrg opens (or reopens) a paid period for an org: org + subscription
// -> active, a fresh period starting now, and a recorded paid invoice.
func (s *Store) ActivateOrg(ctx context.Context, orgID, actor, method string, periodDays int, amountPaise int64, reference, notes string) (*models.OrgSubscription, *models.SaaSInvoice, error) {
	sub, err := s.GetSubscription(ctx, orgID)
	if err != nil {
		return nil, nil, err
	}
	plan, err := s.GetPlanByID(ctx, sub.PlanID)
	if err != nil {
		return nil, nil, err
	}
	if periodDays <= 0 {
		periodDays = plan.IntervalDays
	}
	if amountPaise <= 0 {
		amountPaise = plan.PricePaise
	}
	now := Now()
	start, end := now, now.AddDate(0, 0, periodDays)

	next := *sub
	next.Status = models.SubActive
	next.CancelAtPeriodEnd = false
	next.CurrentPeriodStart = &start
	next.CurrentPeriodEnd = &end
	if notes != "" {
		next.Notes = &notes
	}
	if err := s.UpsertSubscription(ctx, &next); err != nil {
		return nil, nil, err
	}
	if err := s.SetOrgStatus(ctx, orgID, models.OrgActive); err != nil {
		return nil, nil, err
	}

	inv := &models.SaaSInvoice{
		OrgID: orgID, AmountPaise: amountPaise, Method: method,
		GSTPercent:  SaaSGSTPercent,
		PeriodStart: &start, PeriodEnd: &end, PaidAt: now,
		Reference: optStrPtr(reference), Notes: optStrPtr(notes),
	}
	// SaaS GST (18% on the taxable base) — gross = what the customer pays.
	inv.TaxPaise = roundPaise(float64(amountPaise) * SaaSGSTPercent / 100.0)
	inv.GrossPaise = amountPaise + inv.TaxPaise
	if actor != "" {
		inv.CreatedBy = &actor
	}
	created, err := s.CreateSaaSInvoice(ctx, inv)
	if err != nil {
		return nil, nil, err
	}
	_ = s.AddOrgEvent(ctx, orgID, actor, "sub.activated", MetaJSON(map[string]any{
		"method": method, "days": periodDays, "amount_paise": amountPaise,
		"period_end": end, "invoice": created.InvoiceNo,
	}))
	out, err := s.GetSubscriptionWithPlan(ctx, orgID)
	return out, created, err
}

// ExtendOrg pushes the current period end out by N days (trial or active).
func (s *Store) ExtendOrg(ctx context.Context, orgID, actor string, days int, notes string) error {
	if days <= 0 {
		days = 30
	}
	sub, err := s.GetSubscription(ctx, orgID)
	if err != nil {
		return err
	}
	base := time.Now().UTC()
	switch sub.Status {
	case models.SubTrial:
		if sub.TrialEndsAt != nil && sub.TrialEndsAt.After(base) {
			base = *sub.TrialEndsAt
		}
	case models.SubActive, models.SubPastDue:
		if sub.CurrentPeriodEnd != nil && sub.CurrentPeriodEnd.After(base) {
			base = *sub.CurrentPeriodEnd
		}
	}
	end := base.AddDate(0, 0, days)
	next := *sub
	next.CurrentPeriodEnd = &end
	if next.Status == models.SubTrial && sub.TrialEndsAt != nil {
		t := end
		next.TrialEndsAt = &t
	}
	if notes != "" {
		next.Notes = &notes
	}
	if err := s.UpsertSubscription(ctx, &next); err != nil {
		return err
	}
	_ = s.AddOrgEvent(ctx, orgID, actor, "sub.extended", MetaJSON(map[string]any{
		"days": days, "period_end": end, "notes": notes,
	}))
	return nil
}

// SuspendOrg immediately stops paid writes (middleware returns 402).
func (s *Store) SuspendOrg(ctx context.Context, orgID, actor, reason string) error {
	sub, err := s.GetSubscription(ctx, orgID)
	if err != nil {
		return err
	}
	next := *sub
	next.Status = models.SubSuspended
	if reason != "" {
		next.Notes = &reason
	}
	if err := s.UpsertSubscription(ctx, &next); err != nil {
		return err
	}
	if err := s.SetOrgStatus(ctx, orgID, models.OrgSuspended); err != nil {
		return err
	}
	return s.AddOrgEvent(ctx, orgID, actor, "sub.suspended", MetaJSON(map[string]any{"reason": reason}))
}

// CancelOrgNow closes the account permanently (manual flow: superadmin action).
func (s *Store) CancelOrgNow(ctx context.Context, orgID, actor, reason string) error {
	sub, err := s.GetSubscription(ctx, orgID)
	if err != nil {
		return err
	}
	next := *sub
	next.Status = models.SubCancelled
	next.CancelAtPeriodEnd = true
	if reason != "" {
		next.Notes = &reason
	}
	if err := s.UpsertSubscription(ctx, &next); err != nil {
		return err
	}
	if err := s.SetOrgStatus(ctx, orgID, models.OrgClosed); err != nil {
		return err
	}
	return s.AddOrgEvent(ctx, orgID, actor, "sub.cancelled", MetaJSON(map[string]any{"reason": reason}))
}

// ApplyDueTransitions is the daily billing job: trials past their end date
// expire; active periods past their end go past_due; past_due beyond a 3-day
// grace suspends. Every transition is audited via org_events. Reminder e-mails
// are hook points left to internal/mail (log-only today).
func (s *Store) ApplyDueTransitions(ctx context.Context, now time.Time) (expired, pastDue, suspended int, err error) {
	orgs, err := s.ListOrganizations(ctx, "")
	if err != nil {
		return 0, 0, 0, err
	}
	for _, org := range orgs {
		sub, err := s.GetSubscription(ctx, org.ID)
		if err != nil || sub == nil {
			continue
		}
		switch sub.Status {
		case models.SubTrial:
			if sub.TrialEndsAt != nil && !sub.TrialEndsAt.After(now) {
				next := *sub
				next.Status = models.SubExpired
				_ = s.UpsertSubscription(ctx, &next)
				_ = s.SetOrgStatus(ctx, org.ID, models.OrgExpired)
				_ = s.AddOrgEvent(ctx, org.ID, "system", "sub.expired", MetaJSON(map[string]any{"trial_ended": true}))
				expired++
			}
		case models.SubActive:
			if sub.CurrentPeriodEnd != nil && !sub.CurrentPeriodEnd.After(now) {
				next := *sub
				next.Status = models.SubPastDue
				_ = s.UpsertSubscription(ctx, &next)
				_ = s.SetOrgStatus(ctx, org.ID, models.OrgPastDue)
				_ = s.AddOrgEvent(ctx, org.ID, "system", "sub.past_due", MetaJSON(map[string]any{}))
				pastDue++
			}
		case models.SubPastDue:
			if sub.CurrentPeriodEnd != nil && now.Sub(*sub.CurrentPeriodEnd) > 3*24*time.Hour {
				_ = s.SuspendOrg(ctx, org.ID, "system", "unpaid beyond grace")
				suspended++
			}
		}
	}
	return expired, pastDue, suspended, nil
}

// ListSubscriptions returns every subscription for the platform dashboard.
func (s *Store) ListSubscriptions(ctx context.Context) ([]models.OrgSubscription, error) {
	rows, err := s.DB.QueryContext(ctx,
		`SELECT org_id, plan_id, status, trial_ends_at, current_period_start, current_period_end, cancel_at_period_end, notes, updated_at
		 FROM org_subscriptions ORDER BY updated_at DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []models.OrgSubscription
	for rows.Next() {
		sub, err := scanSubscription(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *sub)
	}
	return out, rows.Err()
}
