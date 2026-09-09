package store

// Rotating sessions (auth_refresh) for owner-account and platform-admin
// logins. Staff continue to use the legacy refresh_tokens table; both share
// the same rotating single-use hashed-token semantics.

import (
	"context"
	"database/sql"
	"time"

	"foodpos/backend/internal/httpx"
)

type Session struct {
	ID        string
	Scope     string
	ActorID   string
	OrgID     string
	OutletID  string
	ExpiresAt time.Time
	Revoked   bool
}

func (s *Store) CreateSession(ctx context.Context, scope, actorID, tokenHash string, expiresAt time.Time) error {
	_, err := s.DB.ExecContext(ctx,
		`INSERT INTO auth_refresh (id, scope, actor_id, token_hash, expires_at, created_at)
		 VALUES (?, ?, ?, ?, ?, ?)`,
		NewID("sr"), scope, actorID, tokenHash, TimeStr(expiresAt), TimeStr(Now()))
	return err
}

// CreateStaffSession persists a staff session with its tenant binding so a
// refresh can re-issue the full claim set.
func (s *Store) CreateStaffSession(ctx context.Context, staffID, orgID, outletID, tokenHash string, expiresAt time.Time) error {
	_, err := s.DB.ExecContext(ctx,
		`INSERT INTO auth_refresh (id, scope, actor_id, org_id, outlet_id, token_hash, expires_at, created_at)
		 VALUES (?, 'staff', ?, ?, ?, ?, ?, ?)`,
		NewID("sr"), staffID, orgID, outletID, tokenHash, TimeStr(expiresAt), TimeStr(Now()))
	return err
}

func (s *Store) GetSession(ctx context.Context, tokenHash string) (*Session, error) {
	var sess Session
	var expires string
	var revoked, orgID, outletID sql.NullString
	err := s.DB.QueryRowContext(ctx,
		`SELECT id, scope, actor_id, org_id, outlet_id, expires_at, revoked_at FROM auth_refresh WHERE token_hash = ?`, tokenHash).
		Scan(&sess.ID, &sess.Scope, &sess.ActorID, &orgID, &outletID, &expires, &revoked)
	if err == sql.ErrNoRows {
		return nil, httpx.NewError(401, "invalid_refresh_token", "Refresh token is invalid")
	}
	if err != nil {
		return nil, err
	}
	sess.ExpiresAt = ParseTime(expires)
	sess.Revoked = revoked.Valid
	if orgID.Valid {
		sess.OrgID = orgID.String
	}
	if outletID.Valid {
		sess.OutletID = outletID.String
	}
	return &sess, nil
}

func (s *Store) RevokeSession(ctx context.Context, id string) error {
	_, err := s.DB.ExecContext(ctx,
		`UPDATE auth_refresh SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL`, TimeStr(Now()), id)
	return err
}

// RevokeAllSessions revokes every live session of an actor (logout everywhere).
func (s *Store) RevokeAllSessions(ctx context.Context, scope, actorID string) error {
	_, err := s.DB.ExecContext(ctx,
		`UPDATE auth_refresh SET revoked_at = ? WHERE scope = ? AND actor_id = ? AND revoked_at IS NULL`,
		TimeStr(Now()), scope, actorID)
	return err
}
