package store

import (
	"context"
	"database/sql"
	"strings"
	"time"

	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/models"
)

// ---- Refresh tokens (rotating, hashed at rest) ----

type RefreshToken struct {
	ID        string
	StaffID   string
	ExpiresAt time.Time
	Revoked   bool
}

func (s *Store) CreateRefreshToken(ctx context.Context, staffID, tokenHash string, expiresAt time.Time) error {
	_, err := s.DB.ExecContext(ctx, `INSERT INTO refresh_tokens (id, staff_id, token_hash, expires_at, created_at)
		VALUES (?, ?, ?, ?, ?)`, NewID("rt"), staffID, tokenHash, TimeStr(expiresAt), TimeStr(Now()))
	return err
}

func (s *Store) GetRefreshToken(ctx context.Context, tokenHash string) (*RefreshToken, error) {
	var rt RefreshToken
	var expires, created string
	var revoked sql.NullString
	err := s.DB.QueryRowContext(ctx, `SELECT id, staff_id, expires_at, revoked_at, created_at
		FROM refresh_tokens WHERE token_hash = ?`, tokenHash).
		Scan(&rt.ID, &rt.StaffID, &expires, &revoked, &created)
	if err == sql.ErrNoRows {
		return nil, httpx.NewError(401, "invalid_refresh_token", "Refresh token is invalid")
	}
	if err != nil {
		return nil, err
	}
	rt.ExpiresAt = ParseTime(expires)
	rt.Revoked = revoked.Valid
	return &rt, nil
}

func (s *Store) RevokeRefreshToken(ctx context.Context, id string) error {
	_, err := s.DB.ExecContext(ctx, `UPDATE refresh_tokens SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL`, TimeStr(Now()), id)
	return err
}

// ---- Staff (partial update, B3) ----

func (s *Store) UpdateStaff(ctx context.Context, id string, p models.StaffPatch, pinHash *string) (*models.Staff, error) {
	if _, err := s.GetStaff(ctx, id); err != nil {
		return nil, err
	}
	sets := []string{}
	args := []any{}
	add := func(col string, v any) {
		sets = append(sets, col+" = ?")
		args = append(args, v)
	}
	if p.Name != nil {
		add("name", *p.Name)
	}
	if p.Role != nil {
		add("role", *p.Role)
	}
	if p.Mobile != nil {
		add("mobile", *p.Mobile)
	}
	if p.AvatarURL != nil {
		add("avatar_url", *p.AvatarURL)
	}
	if p.IsActive != nil {
		add("is_active", b2i(*p.IsActive))
	}
	if pinHash != nil {
		add("pin_hash", *pinHash)
	}
	if len(sets) > 0 {
		args = append(args, id)
		if _, err := s.DB.ExecContext(ctx, `UPDATE staff SET `+strings.Join(sets, ", ")+` WHERE id = ?`, args...); err != nil {
			return nil, err
		}
	}
	row, err := s.GetStaff(ctx, id)
	if err != nil {
		return nil, err
	}
	return &row.Staff, nil
}
