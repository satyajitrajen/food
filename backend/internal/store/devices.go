package store

import (
	"context"
	"time"
)

// UpsertDeviceToken registers or updates an FCM device token for an outlet and staff member.
func (s *Store) UpsertDeviceToken(ctx context.Context, token, orgID, outletID, staffID, platform string) error {
	now := time.Now().UTC()
	_, err := s.DB.ExecContext(ctx, `
		INSERT INTO device_tokens (token, org_id, outlet_id, staff_id, platform, updated_at)
		VALUES (?, ?, ?, ?, ?, ?)
		ON CONFLICT (token) DO UPDATE SET
			org_id = excluded.org_id,
			outlet_id = excluded.outlet_id,
			staff_id = excluded.staff_id,
			platform = excluded.platform,
			updated_at = excluded.updated_at
	`, token, orgID, outletID, staffID, platform, now)
	return err
}

// DeleteDeviceToken removes a device token when staff logs out or revokes notifications.
func (s *Store) DeleteDeviceToken(ctx context.Context, token string) error {
	_, err := s.DB.ExecContext(ctx, `DELETE FROM device_tokens WHERE token = ?`, token)
	return err
}

// ListDeviceTokensByOutlet returns all FCM tokens registered to a specific outlet.
func (s *Store) ListDeviceTokensByOutlet(ctx context.Context, outletID string) ([]string, error) {
	rows, err := s.DB.QueryContext(ctx, `SELECT token FROM device_tokens WHERE outlet_id = ?`, outletID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var tokens []string
	for rows.Next() {
		var tok string
		if err := rows.Scan(&tok); err != nil {
			return nil, err
		}
		tokens = append(tokens, tok)
	}
	return tokens, rows.Err()
}

// ListDeviceTokensByOrg returns all FCM tokens registered across an organization.
func (s *Store) ListDeviceTokensByOrg(ctx context.Context, orgID string) ([]string, error) {
	rows, err := s.DB.QueryContext(ctx, `SELECT token FROM device_tokens WHERE org_id = ?`, orgID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var tokens []string
	for rows.Next() {
		var tok string
		if err := rows.Scan(&tok); err != nil {
			return nil, err
		}
		tokens = append(tokens, tok)
	}
	return tokens, rows.Err()
}
