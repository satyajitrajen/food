// Package store is the SQL repository layer: queries and scanning only,
// no business rules. All money is INTEGER PAISE.
package store

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"time"
)

type Store struct {
	DB *sql.DB
}

func New(db *sql.DB) *Store { return &Store{DB: db} }

// NewID returns a sortable prefixed id: <prefix>-<unixmicros>-<rand4>.
func NewID(prefix string) string {
	b := make([]byte, 2)
	_, _ = rand.Read(b)
	return prefix + "-" + hex.EncodeToString(b) + "-" + randHex(3)
}

func randHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func Now() time.Time { return time.Now().UTC() }

func TimeStr(t time.Time) string { return t.UTC().Format(time.RFC3339Nano) }

func ParseTime(s string) time.Time {
	t, err := time.Parse(time.RFC3339Nano, s)
	if err != nil {
		return time.Time{}
	}
	return t
}

// NextCounter increments and returns the named counter for an outlet.
func (s *Store) NextCounter(ctx context.Context, outletID, kind string) (int, error) {
	var v int
	err := s.DB.QueryRowContext(ctx, `SELECT value FROM counters WHERE outlet_id = ? AND kind = ?`, outletID, kind).Scan(&v)
	switch {
	case err == sql.ErrNoRows:
		_, err = s.DB.ExecContext(ctx, `INSERT INTO counters (outlet_id, kind, value) VALUES (?, ?, 1)`, outletID, kind)
		return 1, err
	case err != nil:
		return 0, err
	}
	v++
	_, err = s.DB.ExecContext(ctx, `UPDATE counters SET value = ? WHERE outlet_id = ? AND kind = ?`, v, outletID, kind)
	return v, err
}
