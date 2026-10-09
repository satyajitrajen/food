package api_test

// Package-level DB lifecycle for the integration suite: once per `go test`
// run the public schema is dropped and recreated, then migrated, so every run
// starts from an empty database (re-runs used to fail on leftover rows:
// email_taken, table_occupied …). Tests skip — never fail — when Postgres is
// unreachable, so DB-free tests in this package still run anywhere.

import (
	"database/sql"
	"fmt"
	"os"
	"testing"

	"foodpos/backend/internal/db"
)

var (
	testDSN   string
	dbSkipMsg string // non-empty → integration tests t.Skip with this reason
)

func TestMain(m *testing.M) {
	testDSN = os.Getenv("FOODPOS_TEST_DSN")
	if testDSN == "" {
		testDSN = "postgres://foodpos:foodpos@localhost/foodpos_test?sslmode=disable"
	}
	if err := resetTestDB(testDSN); err != nil {
		dbSkipMsg = "integration DB unavailable: " + err.Error()
	}
	os.Exit(m.Run())
}

func resetTestDB(dsn string) error {
	d, err := db.Open(dsn)
	if err != nil {
		return err
	}
	defer d.Close()
	if _, err := d.Exec(`DROP SCHEMA public CASCADE; CREATE SCHEMA public;`); err != nil {
		return fmt.Errorf("reset schema: %w", err)
	}
	return db.Migrate(d)
}

// openTestDB opens the (already reset + migrated) test database or skips.
func openTestDB(t *testing.T) *sql.DB {
	t.Helper()
	if dbSkipMsg != "" {
		t.Skip(dbSkipMsg)
	}
	d, err := db.Open(testDSN)
	if err != nil {
		t.Skip("integration DB unavailable: " + err.Error())
	}
	t.Cleanup(func() { _ = d.Close() })
	if err := db.Migrate(d); err != nil {
		t.Fatal(err)
	}
	return d
}
