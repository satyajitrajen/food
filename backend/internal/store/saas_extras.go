package store

// Extra SaaS store operations: account tokens, org-code rotation, plan-limit
// counts, by-id outlet lookups for route hardening, and audit writes.

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"time"

	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/models"
)

// ---- Account tokens (email verify / password reset) ----

type AccountTokenKind string

const (
	TokenVerify AccountTokenKind = "verify"
	TokenReset  AccountTokenKind = "reset"
)

// CreateAccountToken issues a rotating single-use token (hash stored).
func (s *Store) CreateAccountToken(ctx context.Context, accountID string, kind AccountTokenKind, ttl time.Duration) (string, error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	token := hex.EncodeToString(raw)
	hash := authTokenHash(token)
	_, err := s.DB.ExecContext(ctx,
		`INSERT INTO account_tokens (id, account_id, kind, token_hash, expires_at, created_at)
		 VALUES (?, ?, ?, ?, ?, ?)`,
		NewID("at"), accountID, string(kind), hash, TimeStr(Now().Add(ttl)), TimeStr(Now()))
	if err != nil {
		return "", err
	}
	return token, nil
}

// ConsumeAccountToken validates + marks used and returns the account id.
func (s *Store) ConsumeAccountToken(ctx context.Context, rawToken string, kind AccountTokenKind) (string, error) {
	var accountID string
	var usedAt sql.NullString
	var expires string
	err := s.DB.QueryRowContext(ctx,
		`SELECT account_id, expires_at, used_at FROM account_tokens WHERE token_hash = ? AND kind = ?`,
		authTokenHash(rawToken), string(kind)).Scan(&accountID, &expires, &usedAt)
	if err == sql.ErrNoRows {
		return "", httpx.NewError(400, "invalid_token", "Token is invalid or already used")
	}
	if err != nil {
		return "", err
	}
	if usedAt.Valid || time.Now().After(ParseTime(expires)) {
		return "", httpx.NewError(400, "invalid_token", "Token is invalid or already used")
	}
	if _, err := s.DB.ExecContext(ctx, `UPDATE account_tokens SET used_at = ? WHERE token_hash = ?`,
		TimeStr(Now()), authTokenHash(rawToken)); err != nil {
		return "", err
	}
	return accountID, nil
}

func (s *Store) SetAccountEmailVerified(ctx context.Context, accountID string, verified bool) error {
	v := 0
	if verified {
		v = 1
	}
	_, err := s.DB.ExecContext(ctx, `UPDATE accounts SET email_verified = ? WHERE id = ?`, v, accountID)
	return err
}

func (s *Store) UpdateAccountPassword(ctx context.Context, accountID, newHash string) error {
	_, err := s.DB.ExecContext(ctx, `UPDATE accounts SET password_hash = ? WHERE id = ?`, newHash, accountID)
	return err
}

func authTokenHash(t string) string {
	sum := sha256.Sum256([]byte(t))
	return hex.EncodeToString(sum[:])
}

// ---- Org code rotation ----

// RotateOrgCode revokes the org's current code and issues a fresh one.
func (s *Store) RotateOrgCode(ctx context.Context, orgID string) (string, error) {
	code, err := newOrgCode()
	if err != nil {
		return "", err
	}
	if _, err := s.DB.ExecContext(ctx, `UPDATE org_codes SET active = 0 WHERE org_id = ?`, orgID); err != nil {
		return "", err
	}
	_, err = s.DB.ExecContext(ctx,
		`INSERT INTO org_codes (org_id, code, active, created_at) VALUES (?, ?, 1, ?)`,
		orgID, code, TimeStr(Now()))
	if err != nil {
		return "", err
	}
	return code, nil
}

// ---- Limits ----

func (s *Store) CountStaff(ctx context.Context, orgID string) (int, error) {
	var n int
	err := s.DB.QueryRowContext(ctx, `SELECT COUNT(*) FROM staff WHERE org_id = ?`, orgID).Scan(&n)
	return n, err
}

// ---- By-id outlet lookups (route hardening) ----

func (s *Store) OutletOfOrder(ctx context.Context, id string) (string, error) {
	var o string
	err := s.DB.QueryRowContext(ctx, `SELECT outlet_id FROM orders WHERE id = ?`, id).Scan(&o)
	if err == sql.ErrNoRows {
		return "", httpx.ErrNotFound
	}
	return o, err
}

func (s *Store) OutletOfMenuItem(ctx context.Context, id string) (string, error) {
	var o string
	err := s.DB.QueryRowContext(ctx, `SELECT outlet_id FROM menu_items WHERE id = ?`, id).Scan(&o)
	if err == sql.ErrNoRows {
		return "", httpx.ErrNotFound
	}
	return o, err
}

func (s *Store) OutletOfKOT(ctx context.Context, id string) (string, error) {
	var o string
	err := s.DB.QueryRowContext(ctx, `SELECT outlet_id FROM kots WHERE id = ?`, id).Scan(&o)
	if err == sql.ErrNoRows {
		return "", httpx.ErrNotFound
	}
	return o, err
}

// OutletOfOutlet returns the org owning an outlet (guard for /outlets/{id}).
func (s *Store) OrgOfOutlet(ctx context.Context, id string) (string, error) {
	var o string
	err := s.DB.QueryRowContext(ctx, `SELECT org_id FROM outlets WHERE id = ?`, id).Scan(&o)
	if err == sql.ErrNoRows {
		return "", httpx.ErrNotFound
	}
	return o, err
}

// ---- Audit ----

// Audit inserts a row into audit_log with tenant attribution. meta is a JSON
// string (or "").
func (s *Store) Audit(ctx context.Context, orgID, outletID, staffID, action, entity, entityID, meta string) error {
	_, err := s.DB.ExecContext(ctx,
		`INSERT INTO audit_log (id, ts, staff_id, action, entity, entity_id, meta, org_id, outlet_id)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		NewID("au"), TimeStr(Now()), orNil(staffID), action, entity, entityID, orNil(meta),
		orNil(orgID), orNil(outletID))
	return err
}

// ---- Invoice fetch (PDF download) ----

func (s *Store) GetSaaSInvoice(ctx context.Context, id string) (*models.SaaSInvoice, error) {
	var inv models.SaaSInvoice
	var pStart, pEnd, paidAt, created string
	var ref, notes, by sql.NullString
	err := s.DB.QueryRowContext(ctx,
		`SELECT id, org_id, invoice_no, amount_paise, gst_percent, tax_paise, gross_paise, method,
		        period_start, period_end, paid_at, reference, notes, created_by, created_at
		 FROM saas_invoices WHERE id = ?`, id).
		Scan(&inv.ID, &inv.OrgID, &inv.InvoiceNo, &inv.AmountPaise, &inv.GSTPercent,
			&inv.TaxPaise, &inv.GrossPaise, &inv.Method,
			&pStart, &pEnd, &paidAt, &ref, &notes, &by, &created)
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	if err != nil {
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
