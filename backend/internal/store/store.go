// Package store is the SQL repository layer: queries and scanning only,
// no business rules. All money is INTEGER PAISE.
package store

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"time"

	_ "time/tzdata" // outlet timezones resolve on minimal images too

	"foodpos/backend/internal/db"
)

type Store struct {
	DB *sql.DB
}

func New(db *sql.DB) *Store { return &Store{DB: db} }

// Querier is satisfied by *sql.DB and *sql.Tx so helpers can run either
// standalone or inside a caller's transaction.
type Querier interface {
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
	QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error)
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
}

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

// TimeStr formats a timestamp for TEXT storage: fixed-width UTC (see
// db.TimeLayout) so string comparison is chronological.
func TimeStr(t time.Time) string { return t.UTC().Format(db.TimeLayout) }

// ParseTime accepts both the fixed-width layout and legacy RFC3339Nano rows.
func ParseTime(s string) time.Time {
	t, err := time.Parse(time.RFC3339Nano, s)
	if err != nil {
		return time.Time{}
	}
	return t
}

// NextCounter atomically increments and returns the named counter for an
// outlet. Pass a *sql.Tx as q to roll the increment back with the caller's
// transaction (nil uses the pool).
func (s *Store) NextCounter(ctx context.Context, q Querier, outletID, kind string) (int, error) {
	if q == nil {
		q = s.DB
	}
	var v int
	err := q.QueryRowContext(ctx, `INSERT INTO counters (outlet_id, kind, value) VALUES (?, ?, 1)
		ON CONFLICT (outlet_id, kind) DO UPDATE SET value = counters.value + 1
		RETURNING value`, outletID, kind).Scan(&v)
	return v, err
}

// withTx runs fn inside a transaction, committing on nil error.
func (s *Store) withTx(ctx context.Context, fn func(tx *sql.Tx) error) error {
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()
	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit()
}
