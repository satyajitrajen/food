// Package db opens the PostgreSQL database and runs embedded migrations.
//
// The codebase was originally written for SQLite and uses `?` placeholders,
// SQLite LIKE semantics, Go time.Time/bool arguments and INTEGER booleans.
// Instead of rewriting every query, the "pgq" driver below wraps lib/pq and
// translates at the driver boundary:
//   - `?` placeholders → $1, $2, ... (outside string literals)
//   - LIKE → ILIKE (SQLite LIKE is case-insensitive for ASCII)
//   - time.Time args → RFC3339Nano strings (matches store.TimeStr)
//   - bool args → int64 0/1 (matches INTEGER columns)
package db

import (
	"context"
	"database/sql"
	"database/sql/driver"
	"embed"
	"fmt"
	"log/slog"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/lib/pq"
)

//go:embed migrations/*.sql
var migrationFS embed.FS

// Open connects to the PostgreSQL database using the given DSN.
func Open(dsn string) (*sql.DB, error) {
	d, err := sql.Open("pgq", dsn)
	if err != nil {
		return nil, fmt.Errorf("open postgres: %w", err)
	}
	if err := d.Ping(); err != nil {
		return nil, fmt.Errorf("ping postgres: %w", err)
	}
	d.SetMaxOpenConns(20)
	return d, nil
}

// ---- pgq driver: lib/pq with SQLite-compat rewriting ----

func init() {
	sql.Register("pgq", pgDriver{})
}

type pgDriver struct{}

func (pgDriver) Open(name string) (driver.Conn, error) {
	c, err := (&pq.Driver{}).Open(name)
	if err != nil {
		return nil, err
	}
	return pgConn{c}, nil
}

type pgConn struct{ driver.Conn }

var (
	_ driver.QueryerContext = pgConn{}
	_ driver.ExecerContext   = pgConn{}
	_ driver.Pinger          = pgConn{}
	_ driver.ConnBeginTx     = pgConn{}
)

func (c pgConn) QueryContext(ctx context.Context, q string, args []driver.NamedValue) (driver.Rows, error) {
	return c.Conn.(driver.QueryerContext).QueryContext(ctx, Rewrite(q), Coerce(args))
}

func (c pgConn) ExecContext(ctx context.Context, q string, args []driver.NamedValue) (driver.Result, error) {
	return c.Conn.(driver.ExecerContext).ExecContext(ctx, Rewrite(q), Coerce(args))
}

func (c pgConn) Ping(ctx context.Context) error {
	if p, ok := c.Conn.(driver.Pinger); ok {
		return p.Ping(ctx)
	}
	return nil
}

func (c pgConn) BeginTx(ctx context.Context, opts driver.TxOptions) (driver.Tx, error) {
	return c.Conn.(driver.ConnBeginTx).BeginTx(ctx, opts)
}

func (c pgConn) Prepare(q string) (driver.Stmt, error) {
	st, err := c.Conn.Prepare(Rewrite(q))
	if err != nil {
		return nil, err
	}
	return pgStmt{st}, nil
}

type pgStmt struct{ driver.Stmt }

func (s pgStmt) Query(args []driver.Value) (driver.Rows, error) {
	return s.Stmt.Query(coerceValues(args))
}

func (s pgStmt) Exec(args []driver.Value) (driver.Result, error) {
	return s.Stmt.Exec(coerceValues(args))
}

// Rewrite converts SQLite-style SQL to PostgreSQL: ? → $N and LIKE → ILIKE.
// Placeholders inside single-quoted literals are left untouched.
func Rewrite(q string) string {
	if !strings.ContainsRune(q, '?') && !strings.Contains(q, "LIKE") {
		return q
	}
	var b strings.Builder
	b.Grow(len(q) + len(q)/8)
	n := 0
	inSingle := false
	for i := 0; i < len(q); i++ {
		ch := q[i]
		if inSingle {
			b.WriteByte(ch)
			if ch == '\'' {
				if i+1 < len(q) && q[i+1] == '\'' {
					b.WriteByte('\'')
					i++
					continue
				}
				inSingle = false
			}
			continue
		}
		switch ch {
		case '\'':
			inSingle = true
			b.WriteByte(ch)
		case '?':
			n++
			b.WriteString("$")
			b.WriteString(strconv.Itoa(n))
		case 'L':
			if i+4 <= len(q) && q[i:i+4] == "LIKE" &&
				(i == 0 || !isSQLWordByte(q[i-1])) &&
				(i+4 == len(q) || !isSQLWordByte(q[i+4])) {
				b.WriteString("ILIKE")
				i += 3
				continue
			}
			b.WriteByte(ch)
		default:
			b.WriteByte(ch)
		}
	}
	return b.String()
}

func isSQLWordByte(b byte) bool {
	return b == '_' || (b >= '0' && b <= '9') || (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z')
}

// Coerce converts time.Time args to RFC3339Nano strings and bools to int64
// so TEXT-timestamp / INTEGER-boolean columns behave like they did on SQLite.
func Coerce(args []driver.NamedValue) []driver.NamedValue {
	changed := false
	for i := range args {
		switch v := args[i].Value.(type) {
		case time.Time:
			args[i].Value = v.UTC().Format(time.RFC3339Nano)
			changed = true
		case bool:
			if v {
				args[i].Value = int64(1)
			} else {
				args[i].Value = int64(0)
			}
			changed = true
		}
	}
	if changed {
		for i := range args {
			args[i].Ordinal = i + 1
		}
	}
	return args
}

func coerceValues(args []driver.Value) []driver.Value {
	for i, v := range args {
		switch t := v.(type) {
		case time.Time:
			args[i] = t.UTC().Format(time.RFC3339Nano)
		case bool:
			if t {
				args[i] = int64(1)
			} else {
				args[i] = int64(0)
			}
		}
	}
	return args
}

// Migrate applies any unapplied *.sql migrations in filename order.
func Migrate(d *sql.DB) error {
	if _, err := d.Exec(`CREATE TABLE IF NOT EXISTS schema_migrations (
		name TEXT PRIMARY KEY,
		applied_at TEXT NOT NULL
	)`); err != nil {
		return fmt.Errorf("create schema_migrations: %w", err)
	}

	entries, err := migrationFS.ReadDir("migrations")
	if err != nil {
		return fmt.Errorf("read migrations: %w", err)
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		names = append(names, e.Name())
	}
	sort.Strings(names)

	for _, name := range names {
		var exists int
		if err := d.QueryRow(`SELECT COUNT(*) FROM schema_migrations WHERE name = $1`, name).Scan(&exists); err != nil {
			return fmt.Errorf("check migration %s: %w", name, err)
		}
		if exists > 0 {
			continue
		}
		body, err := migrationFS.ReadFile("migrations/" + name)
		if err != nil {
			return fmt.Errorf("read migration %s: %w", name, err)
		}
		tx, err := d.Begin()
		if err != nil {
			return fmt.Errorf("begin migration %s: %w", name, err)
		}
		if _, err := tx.Exec(string(body)); err != nil {
			_ = tx.Rollback()
			return fmt.Errorf("apply migration %s: %w", name, err)
		}
		if _, err := tx.Exec(`INSERT INTO schema_migrations (name, applied_at) VALUES ($1, now())`, name); err != nil {
			_ = tx.Rollback()
			return fmt.Errorf("record migration %s: %w", name, err)
		}
		if err := tx.Commit(); err != nil {
			return fmt.Errorf("commit migration %s: %w", name, err)
		}
		slog.Info("migration applied", "name", name)
	}
	return nil
}
