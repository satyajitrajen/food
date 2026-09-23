package store

// Staff attendance ledger: auto clock-in on staff login and auto clock-out on
// logout. Idempotent — a staff member never gets two open sessions.

import (
	"context"
	"database/sql"

	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/models"
)

// ClockInStaff opens an attendance session for the staff member. Idempotent:
// an already-open entry is returned as-is (session restores and repeated
// logins never create duplicates).
func (s *Store) ClockInStaff(ctx context.Context, orgID, outletID, staffID, staffName string) (*models.AttendanceEntry, error) {
	var openID string
	err := s.DB.QueryRowContext(ctx,
		`SELECT id FROM staff_attendance WHERE staff_id = ? AND clock_out IS NULL ORDER BY clock_in DESC LIMIT 1`, staffID).
		Scan(&openID)
	if err == nil {
		return s.GetAttendance(ctx, openID)
	}
	if err != httpx.ErrNotFound {
		return nil, err
	}
	id := NewID("att")
	now := Now()
	if _, err := s.DB.ExecContext(ctx,
		`INSERT INTO staff_attendance (id, org_id, outlet_id, staff_id, staff_name, clock_in, created_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?)`,
		id, orgID, outletID, staffID, staffName, TimeStr(now), TimeStr(now)); err != nil {
		return nil, err
	}
	return s.GetAttendance(ctx, id)
}

// ClockOutStaff closes the most recent open session for the staff member.
// Returns nil (no error) when there is nothing open — every close path
// (logout, refresh revoke, explicit endpoint) is a safe no-op then.
func (s *Store) ClockOutStaff(ctx context.Context, staffID string) (*models.AttendanceEntry, error) {
	var openID string
	err := s.DB.QueryRowContext(ctx,
		`SELECT id FROM staff_attendance WHERE staff_id = ? AND clock_out IS NULL ORDER BY clock_in DESC LIMIT 1`, staffID).
		Scan(&openID)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	if _, err := s.DB.ExecContext(ctx,
		`UPDATE staff_attendance SET clock_out = ? WHERE id = ? AND clock_out IS NULL`, TimeStr(Now()), openID); err != nil {
		return nil, err
	}
	return s.GetAttendance(ctx, openID)
}

func (s *Store) GetAttendance(ctx context.Context, id string) (*models.AttendanceEntry, error) {
	rows := s.DB.QueryRowContext(ctx, attendanceCols+` WHERE id = ?`, id)
	return scanAttendance(rows)
}

const attendanceCols = `SELECT id, org_id, outlet_id, staff_id, staff_name, clock_in, clock_out FROM staff_attendance`

func scanAttendance(sc interface{ Scan(...any) error }) (*models.AttendanceEntry, error) {
	var a models.AttendanceEntry
	var clockIn string
	var clockOut sql.NullString
	if err := sc.Scan(&a.ID, &a.OrgID, &a.OutletID, &a.StaffID, &a.StaffName, &clockIn, &clockOut); err != nil {
		if err == sql.ErrNoRows {
			return nil, httpx.ErrNotFound
		}
		return nil, err
	}
	a.ClockIn = ParseTime(clockIn)
	if clockOut.Valid && clockOut.String != "" {
		t := ParseTime(clockOut.String)
		a.ClockOut = &t
	}
	return &a, nil
}

// ListAttendance returns attendance entries for an org, optionally scoped to
// one staff member and a date (YYYY-MM-DD, UTC) window.
func (s *Store) ListAttendance(ctx context.Context, orgID, staffID, fromDay, toDay string, limit int) ([]models.AttendanceEntry, error) {
	q := attendanceCols + ` WHERE org_id = ?`
	args := []any{orgID}
	if staffID != "" {
		q += ` AND staff_id = ?`
		args = append(args, staffID)
	}
	if fromDay != "" {
		q += ` AND substr(clock_in, 1, 10) >= ?`
		args = append(args, fromDay)
	}
	if toDay != "" {
		q += ` AND substr(clock_in, 1, 10) <= ?`
		args = append(args, toDay)
	}
	if limit <= 0 {
		limit = 200
	}
	q += ` ORDER BY clock_in DESC LIMIT ?`
	args = append(args, limit)
	rows, err := s.DB.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []models.AttendanceEntry{}
	for rows.Next() {
		a, err := scanAttendance(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *a)
	}
	return out, rows.Err()
}
