package store

// SaaS store: organizations, owner accounts, platform admins, plans,
// subscriptions, invoices, org events and terminal bootstrap. Billing is
// manual-first (superadmin activates on receipt) — the gateway adapter plugs
// in later; see internal/billing.

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/json"
	"math/big"
	"strconv"
	"strings"
	"time"

	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/models"
)

// ---- Lookup helpers ----

func scanOrg(sc interface{ Scan(...any) error }) (*models.Organization, error) {
	var o models.Organization
	var created, updated string
	if err := sc.Scan(&o.ID, &o.Name, &o.Email, &o.GSTIN, &o.Status, &created, &updated); err != nil {
		return nil, err
	}
	o.CreatedAt = ParseTime(created)
	o.UpdatedAt = ParseTime(updated)
	return &o, nil
}

func scanPlan(sc interface{ Scan(...any) error }) (*models.Plan, error) {
	var p models.Plan
	var active int
	if err := sc.Scan(&p.ID, &p.Code, &p.Name, &p.PricePaise, &p.IntervalDays, &p.MaxOutlets, &p.MaxStaff, &p.TrialDays, &active); err != nil {
		return nil, err
	}
	p.IsActive = active == 1
	return &p, nil
}

func scanSubscription(sc interface{ Scan(...any) error }) (*models.OrgSubscription, error) {
	var s models.OrgSubscription
	var trial, pStart, pEnd, updated string
	var cancel int
	var notes sql.NullString
	if err := sc.Scan(&s.OrgID, &s.PlanID, &s.Status, &trial, &pStart, &pEnd, &cancel, &notes, &updated); err != nil {
		return nil, err
	}
	s.TrialEndsAt = parseOptTime(trial)
	s.CurrentPeriodStart = parseOptTime(pStart)
	s.CurrentPeriodEnd = parseOptTime(pEnd)
	s.CancelAtPeriodEnd = cancel == 1
	if notes.Valid {
		s.Notes = &notes.String
	}
	s.UpdatedAt = ParseTime(updated)
	return &s, nil
}

func parseOptTime(s string) *time.Time {
	if s == "" {
		return nil
	}
	t := ParseTime(s)
	return &t
}

// ---- Organizations ----

func (s *Store) GetOrganization(ctx context.Context, id string) (*models.Organization, error) {
	var o models.Organization
	var created, updated string
	err := s.DB.QueryRowContext(ctx, `SELECT id, name, email, gstin, status, created_at, updated_at FROM organizations WHERE id = ?`, id).
		Scan(&o.ID, &o.Name, &o.Email, &o.GSTIN, &o.Status, &created, &updated)
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	o.CreatedAt = ParseTime(created)
	o.UpdatedAt = ParseTime(updated)
	return &o, nil
}

func (s *Store) ListOrganizations(ctx context.Context, status string) ([]models.Organization, error) {
	q := `SELECT id, name, email, gstin, status, created_at, updated_at FROM organizations`
	args := []any{}
	if status != "" {
		q += ` WHERE status = ?`
		args = append(args, status)
	}
	q += ` ORDER BY created_at DESC`
	rows, err := s.DB.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []models.Organization
	for rows.Next() {
		o, err := scanOrg(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *o)
	}
	return out, rows.Err()
}

func (s *Store) SetOrgStatus(ctx context.Context, orgID, status string) error {
	_, err := s.DB.ExecContext(ctx, `UPDATE organizations SET status = ?, updated_at = ? WHERE id = ?`,
		status, TimeStr(Now()), orgID)
	return err
}

func (s *Store) GetOrgByCode(ctx context.Context, code string) (*models.Organization, error) {
	var orgID string
	err := s.DB.QueryRowContext(ctx,
		`SELECT org_id FROM org_codes WHERE code = ? AND active = 1`, code).Scan(&orgID)
	if err == sql.ErrNoRows {
		return nil, httpx.NewError(404, "invalid_org_code", "Unknown or inactive organization code")
	}
	if err != nil {
		return nil, err
	}
	return s.GetOrganization(ctx, orgID)
}

// ---- Accounts ----

func (s *Store) CreateAccount(ctx context.Context, a models.AccountCreate) (*models.Account, error) {
	id := NewID("ac")
	_, err := s.DB.ExecContext(ctx,
		`INSERT INTO accounts (id, org_id, name, email, password_hash, role, is_active, created_at)
		 VALUES (?, ?, ?, ?, ?, ?, 1, ?)`,
		id, a.OrgID, a.Name, a.Email, a.PasswordHash, a.Role, TimeStr(Now()))
	if err != nil {
		return nil, err
	}
	row, err := s.GetAccount(ctx, id)
	if err != nil {
		return nil, err
	}
	return &row.Account, nil
}

func scanAccount(sc interface{ Scan(...any) error }) (*models.Account, error) {
	var a models.Account
	var created string
	var active int
	if err := sc.Scan(&a.ID, &a.OrgID, &a.Name, &a.Email, &a.Role, &active, &created); err != nil {
		return nil, err
	}
	a.IsActive = active == 1
	a.CreatedAt = ParseTime(created)
	return &a, nil
}

func (s *Store) GetAccount(ctx context.Context, id string) (*AccountWithPassword, error) {
	var a AccountWithPassword
	var created string
	var active int
	err := s.DB.QueryRowContext(ctx,
		`SELECT id, org_id, name, email, role, is_active, password_hash, created_at FROM accounts WHERE id = ?`, id).
		Scan(&a.ID, &a.OrgID, &a.Name, &a.Email, &a.Role, &active, &a.PasswordHash, &created)
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	a.IsActive = active == 1
	a.CreatedAt = ParseTime(created)
	return &a, nil
}

// GetAccountWithPassword returns the account + password hash for login.
type AccountWithPassword struct {
	models.Account
	PasswordHash string
}

func (s *Store) GetAccountByEmail(ctx context.Context, email string) (*AccountWithPassword, error) {
	var a AccountWithPassword
	var created string
	var active int
	err := s.DB.QueryRowContext(ctx,
		`SELECT id, org_id, name, email, role, is_active, password_hash, created_at FROM accounts WHERE email = ?`, email).
		Scan(&a.ID, &a.OrgID, &a.Name, &a.Email, &a.Role, &active, &a.PasswordHash, &created)
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	a.IsActive = active == 1
	a.CreatedAt = ParseTime(created)
	return &a, nil
}

// ---- Platform admins ----

type AdminWithPassword struct {
	models.PlatformAdmin
	PasswordHash string
}

func (s *Store) CreatePlatformAdmin(ctx context.Context, name, email, pwHash string) (*models.PlatformAdmin, error) {
	id := NewID("pa")
	_, err := s.DB.ExecContext(ctx,
		`INSERT INTO platform_admins (id, name, email, password_hash, created_at) VALUES (?, ?, ?, ?, ?)`,
		id, name, email, pwHash, TimeStr(Now()))
	if err != nil {
		return nil, err
	}
	var a models.PlatformAdmin
	var created string
	if err := s.DB.QueryRowContext(ctx, `SELECT id, name, email, created_at FROM platform_admins WHERE id = ?`, id).
		Scan(&a.ID, &a.Name, &a.Email, &created); err != nil {
		return nil, err
	}
	a.CreatedAt = ParseTime(created)
	return &a, nil
}

func (s *Store) GetPlatformAdminByEmail(ctx context.Context, email string) (*AdminWithPassword, error) {
	var a AdminWithPassword
	var created string
	err := s.DB.QueryRowContext(ctx,
		`SELECT id, name, email, password_hash, created_at FROM platform_admins WHERE email = ?`, email).
		Scan(&a.ID, &a.Name, &a.Email, &a.PasswordHash, &created)
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	a.CreatedAt = ParseTime(created)
	return &a, nil
}

func (s *Store) GetPlatformAdminByID(ctx context.Context, id string) (*models.PlatformAdmin, error) {
	var a models.PlatformAdmin
	var created string
	err := s.DB.QueryRowContext(ctx,
		`SELECT id, name, email, created_at FROM platform_admins WHERE id = ?`, id).
		Scan(&a.ID, &a.Name, &a.Email, &created)
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	a.CreatedAt = ParseTime(created)
	return &a, nil
}

func (s *Store) CountPlatformAdmins(ctx context.Context) (int, error) {
	var n int
	err := s.DB.QueryRowContext(ctx, `SELECT COUNT(*) FROM platform_admins`).Scan(&n)
	return n, err
}

// ---- Plans ----

// SeedDefaultPlan inserts the v1 plan (idempotent) and returns it.
func (s *Store) SeedDefaultPlan(ctx context.Context) (*models.Plan, error) {
	_, err := s.DB.ExecContext(ctx,
		`INSERT INTO plans (id, code, name, price_paise, interval_days, max_outlets, max_staff, trial_days, is_active)
		 VALUES ('plan-pro', 'pro', 'Pro', 149900, 30, 5, 20, 14, 1) ON CONFLICT (code) DO NOTHING`)
	if err != nil {
		return nil, err
	}
	return s.GetPlanByCode(ctx, "pro")
}

func (s *Store) GetPlanByCode(ctx context.Context, code string) (*models.Plan, error) {
	var p models.Plan
	var active int
	err := s.DB.QueryRowContext(ctx,
		`SELECT id, code, name, price_paise, interval_days, max_outlets, max_staff, trial_days, is_active FROM plans WHERE code = ?`, code).
		Scan(&p.ID, &p.Code, &p.Name, &p.PricePaise, &p.IntervalDays, &p.MaxOutlets, &p.MaxStaff, &p.TrialDays, &active)
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	p.IsActive = active == 1
	return &p, nil
}

// ---- Subscriptions ----

const subscriptionCols = `org_id, plan_id, status, trial_ends_at, current_period_start, current_period_end, cancel_at_period_end, notes, updated_at`

func (s *Store) GetSubscription(ctx context.Context, orgID string) (*models.OrgSubscription, error) {
	var sub models.OrgSubscription
	var trial, pStart, pEnd, updated string
	var cancel int
	var notes sql.NullString
	err := s.DB.QueryRowContext(ctx, `SELECT `+subscriptionCols+` FROM org_subscriptions WHERE org_id = ?`, orgID).
		Scan(&sub.OrgID, &sub.PlanID, &sub.Status, &trial, &pStart, &pEnd, &cancel, &notes, &updated)
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	sub.TrialEndsAt = parseOptTime(trial)
	sub.CurrentPeriodStart = parseOptTime(pStart)
	sub.CurrentPeriodEnd = parseOptTime(pEnd)
	sub.CancelAtPeriodEnd = cancel == 1
	if notes.Valid {
		sub.Notes = &notes.String
	}
	sub.UpdatedAt = ParseTime(updated)
	return &sub, nil
}

// GetSubscriptionWithPlan returns the subscription joined to its plan.
func (s *Store) GetSubscriptionWithPlan(ctx context.Context, orgID string) (*models.OrgSubscription, error) {
	sub, err := s.GetSubscription(ctx, orgID)
	if err != nil {
		return nil, err
	}
	plan, err := s.GetPlanByID(ctx, sub.PlanID)
	if err == nil {
		sub.Plan = plan
	}
	return sub, nil
}

func (s *Store) GetPlanByID(ctx context.Context, id string) (*models.Plan, error) {
	var p models.Plan
	var active int
	err := s.DB.QueryRowContext(ctx,
		`SELECT id, code, name, price_paise, interval_days, max_outlets, max_staff, trial_days, is_active FROM plans WHERE id = ?`, id).
		Scan(&p.ID, &p.Code, &p.Name, &p.PricePaise, &p.IntervalDays, &p.MaxOutlets, &p.MaxStaff, &p.TrialDays, &active)
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	p.IsActive = active == 1
	return &p, nil
}

// UpsertSubscription sets the subscription row (used on registration and on
// every activation/reactivation).
func (s *Store) UpsertSubscription(ctx context.Context, sub *models.OrgSubscription) error {
	trial := ""
	if sub.TrialEndsAt != nil {
		trial = TimeStr(*sub.TrialEndsAt)
	}
	pStart := ""
	if sub.CurrentPeriodStart != nil {
		pStart = TimeStr(*sub.CurrentPeriodStart)
	}
	pEnd := ""
	if sub.CurrentPeriodEnd != nil {
		pEnd = TimeStr(*sub.CurrentPeriodEnd)
	}
	notes := any(nil)
	if sub.Notes != nil {
		notes = *sub.Notes
	}
	cancel := 0
	if sub.CancelAtPeriodEnd {
		cancel = 1
	}
	_, err := s.DB.ExecContext(ctx,
		`INSERT INTO org_subscriptions (org_id, plan_id, status, trial_ends_at, current_period_start, current_period_end, cancel_at_period_end, notes, updated_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
		 ON CONFLICT (org_id) DO UPDATE SET
		   plan_id = excluded.plan_id, status = excluded.status,
		   trial_ends_at = excluded.trial_ends_at,
		   current_period_start = excluded.current_period_start,
		   current_period_end = excluded.current_period_end,
		   cancel_at_period_end = excluded.cancel_at_period_end,
		   notes = excluded.notes, updated_at = excluded.updated_at`,
		sub.OrgID, sub.PlanID, sub.Status, trial, pStart, pEnd, cancel, notes, TimeStr(Now()))
	return err
}

// ---- Invoices ----

func (s *Store) CreateSaaSInvoice(ctx context.Context, inv *models.SaaSInvoice) (*models.SaaSInvoice, error) {
	num, err := s.NextCounter(ctx, inv.OrgID, "saas_invoice")
	if err != nil {
		return nil, err
	}
	inv.ID = NewID("si")
	inv.InvoiceNo = "SAAS-INV-" + strconv.Itoa(num)
	periodStart := ""
	if inv.PeriodStart != nil {
		periodStart = TimeStr(*inv.PeriodStart)
	}
	periodEnd := ""
	if inv.PeriodEnd != nil {
		periodEnd = TimeStr(*inv.PeriodEnd)
	}
	ref := any(nil)
	if inv.Reference != nil {
		ref = *inv.Reference
	}
	notes := any(nil)
	if inv.Notes != nil {
		notes = *inv.Notes
	}
	by := any(nil)
	if inv.CreatedBy != nil {
		by = *inv.CreatedBy
	}
	inv.CreatedAt = Now()
	_, err = s.DB.ExecContext(ctx,
		`INSERT INTO saas_invoices (id, org_id, invoice_no, amount_paise, method, period_start, period_end, paid_at, reference, notes, created_by, created_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		inv.ID, inv.OrgID, inv.InvoiceNo, inv.AmountPaise, inv.Method, periodStart, periodEnd,
		TimeStr(inv.PaidAt), ref, notes, by, TimeStr(inv.CreatedAt))
	if err != nil {
		return nil, err
	}
	return inv, nil
}

func (s *Store) ListSaaSInvoices(ctx context.Context, orgID string) ([]models.SaaSInvoice, error) {
	rows, err := s.DB.QueryContext(ctx,
		`SELECT id, org_id, invoice_no, amount_paise, method, period_start, period_end, paid_at, reference, notes, created_by, created_at
		 FROM saas_invoices WHERE org_id = ? ORDER BY created_at DESC`, orgID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []models.SaaSInvoice
	for rows.Next() {
		inv, err := scanInvoice(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *inv)
	}
	return out, rows.Err()
}

func scanInvoice(sc interface{ Scan(...any) error }) (*models.SaaSInvoice, error) {
	var inv models.SaaSInvoice
	var pStart, pEnd, paidAt, created string
	var ref, notes, by sql.NullString
	if err := sc.Scan(&inv.ID, &inv.OrgID, &inv.InvoiceNo, &inv.AmountPaise, &inv.Method,
		&pStart, &pEnd, &paidAt, &ref, &notes, &by, &created); err != nil {
		return nil, err
	}
	inv.PeriodStart = parseOptTime(pStart)
	inv.PeriodEnd = parseOptTime(pEnd)
	inv.PaidAt = ParseTime(paidAt)
	inv.CreatedAt = ParseTime(created)
	if ref.Valid {
		inv.Reference = &ref.String
	}
	if notes.Valid {
		inv.Notes = &notes.String
	}
	if by.Valid {
		inv.CreatedBy = &by.String
	}
	return &inv, nil
}

// ---- Org events ----

func (s *Store) AddOrgEvent(ctx context.Context, orgID, actor, action, meta string) error {
	_, err := s.DB.ExecContext(ctx,
		`INSERT INTO org_events (id, org_id, actor, action, meta, ts) VALUES (?, ?, ?, ?, ?, ?)`,
		NewID("ev"), orgID, orNil(actor), action, meta, TimeStr(Now()))
	return err
}

func (s *Store) ListOrgEvents(ctx context.Context, orgID string) ([]models.OrgEvent, error) {
	rows, err := s.DB.QueryContext(ctx,
		`SELECT id, org_id, actor, action, meta, ts FROM org_events WHERE org_id = ? ORDER BY ts DESC LIMIT 200`, orgID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []models.OrgEvent
	for rows.Next() {
		var e models.OrgEvent
		var actor sql.NullString
		var meta, ts string
		if err := rows.Scan(&e.ID, &e.OrgID, &actor, &e.Action, &meta, &ts); err != nil {
			return nil, err
		}
		if actor.Valid {
			e.Actor = &actor.String
		}
		e.Meta = meta
		e.Ts = ParseTime(ts)
		out = append(out, e)
	}
	return out, rows.Err()
}

// ---- Entitlement (for POS login payloads + offline grace) ----

// GraceDays is how long a terminal keeps working offline after entitlement
// expiry (server denial remains the hard enforcement point).
const GraceDays = 7

func (s *Store) GetEntitlement(ctx context.Context, orgID string) (*models.Entitlement, error) {
	org, err := s.GetOrganization(ctx, orgID)
	if err != nil {
		return nil, err
	}
	sub, err := s.GetSubscription(ctx, orgID)
	if err != nil {
		return nil, err
	}
	e := &models.Entitlement{Status: sub.Status, GraceDays: GraceDays}
	until := time.Time{}
	switch sub.Status {
	case models.SubTrial:
		if sub.TrialEndsAt != nil {
			until = *sub.TrialEndsAt
		}
	case models.SubActive, models.SubPastDue:
		if sub.CurrentPeriodEnd != nil {
			until = *sub.CurrentPeriodEnd
		}
	default:
		until = Now()
	}
	if org.Status == models.OrgSuspended {
		e.Status = models.SubSuspended
		until = Now()
	}
	e.ValidUntil = until.AddDate(0, 0, GraceDays)
	return e, nil
}

// EntitlementOK reports whether the org may perform paid writes right now.
func (s *Store) EntitlementOK(ctx context.Context, orgID string) (bool, error) {
	org, err := s.GetOrganization(ctx, orgID)
	if err != nil {
		return false, err
	}
	if org.Status == models.OrgSuspended || org.Status == models.OrgClosed || org.Status == models.OrgExpired {
		return false, nil
	}
	sub, err := s.GetSubscription(ctx, orgID)
	if err != nil {
		return false, nil // missing subscription = not entitled
	}
	switch sub.Status {
	case models.SubTrial, models.SubActive:
		return true, nil
	default:
		return false, nil
	}
}

// ---- Registration (self-service onboarding) ----

type RegisterResult struct {
	Org          models.Organization
	Account      models.Account
	Outlet       models.Outlet
	Staff        models.Staff
	OrgCode      string
	Plan         *models.Plan
	Subscription *models.OrgSubscription
}

func newOrgCode() (string, error) {
	const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	b := make([]byte, 8)
	for i := range b {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(len(alphabet))))
		if err != nil {
			return "", err
		}
		b[i] = alphabet[n.Int64()]
	}
	return string(b), nil
}

// RegisterOrg provisions a full tenant: org + owner account + org code +
// default plan subscription (trial) + first outlet + initial admin staff.
// Runs in a transaction; password hashes must be precomputed by the caller.
func (s *Store) RegisterOrg(ctx context.Context, name, email, gstin, ownerName, pwHash string,
	outletName, terminal, adminPINHash string) (*RegisterResult, error) {

	plan, err := s.SeedDefaultPlan(ctx)
	if err != nil {
		return nil, err
	}
	orgID := NewID("org")
	now := Now()
	trialEnd := now.AddDate(0, 0, plan.TrialDays)

	code, err := newOrgCode()
	if err != nil {
		return nil, err
	}

	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	if _, err := tx.ExecContext(ctx,
		`INSERT INTO organizations (id, name, email, gstin, status, created_at, updated_at)
		 VALUES (?, ?, ?, ?, 'trial', ?, ?)`,
		orgID, name, email, gstin, TimeStr(now), TimeStr(now)); err != nil {
		return nil, err
	}
	if _, err := tx.ExecContext(ctx,
		`INSERT INTO org_codes (org_id, code, active, created_at) VALUES (?, ?, 1, ?)`,
		orgID, code, TimeStr(now)); err != nil {
		return nil, err
	}
	if _, err := tx.ExecContext(ctx,
		`INSERT INTO accounts (id, org_id, name, email, password_hash, role, is_active, created_at)
		 VALUES (?, ?, ?, ?, ?, 'owner', 1, ?)`,
		NewID("ac"), orgID, ownerName, email, pwHash, TimeStr(now)); err != nil {
		return nil, err
	}
	if _, err := tx.ExecContext(ctx,
		`INSERT INTO org_subscriptions (org_id, plan_id, status, trial_ends_at, current_period_start, current_period_end, cancel_at_period_end, notes, updated_at)
		 VALUES (?, ?, 'trial', ?, ?, NULL, 0, NULL, ?)`,
		orgID, plan.ID, TimeStr(trialEnd), TimeStr(now), TimeStr(now)); err != nil {
		return nil, err
	}
	outletID := NewID("out")
	if _, err := tx.ExecContext(ctx,
		`INSERT INTO outlets (id, org_id, name, address, terminal, gstin, fssai, phone, is_online)
		 VALUES (?, ?, ?, '', ?, '', '', '', 1)`,
		outletID, orgID, outletName, orNil(terminal)); err != nil {
		return nil, err
	}
	staffID := NewID("st")
	if _, err := tx.ExecContext(ctx,
		`INSERT INTO staff (id, org_id, outlet_id, name, role, pin_hash, avatar_url, mobile, is_active)
		 VALUES (?, ?, NULL, ?, 'admin', ?, '', '', 1)`,
		staffID, orgID, ownerName, adminPINHash); err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}

	res := &RegisterResult{OrgCode: code, Plan: plan}
	org, err := s.GetOrganization(ctx, orgID)
	if err != nil {
		return nil, err
	}
	res.Org = *org
	accRow, err := s.GetAccountByEmail(ctx, email)
	if err != nil {
		return nil, err
	}
	res.Account = accRow.Account
	out, err := s.GetOutlet(ctx, outletID)
	if err != nil {
		return nil, err
	}
	res.Outlet = *out
	st, err := s.GetStaff(ctx, staffID)
	if err != nil {
		return nil, err
	}
	res.Staff = st.Staff
	sub, err := s.GetSubscriptionWithPlan(ctx, orgID)
	if err != nil {
		return nil, err
	}
	res.Subscription = sub
	return res, nil
}

// MetaJSON is a convenience for org_events meta payloads.
func MetaJSON(v any) string {
	b, _ := json.Marshal(v)
	return string(b)
}

// orNil converts an empty string to a NULL SQL arg.
func orNil(s string) any {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	return s
}

// optStrPtr converts a string to a *string model field (nil when empty).
func optStrPtr(s string) *string {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	return &s
}
