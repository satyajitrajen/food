// Billing job: run daily (cron) to move subscriptions through their
// lifecycle (trial expiry, period end → past_due, grace → suspend). Reads
// the same env as the server. Reminders/e-mail hooks are log lines today.
package main

import (
	"context"
	"log/slog"
	"os"

	"foodpos/backend/internal/config"
	"foodpos/backend/internal/db"
	"foodpos/backend/internal/store"
)

func main() {
	cfg := config.Load()
	database, err := db.Open(cfg.DSN)
	if err != nil {
		slog.Error("db open failed", "err", err)
		os.Exit(1)
	}
	defer database.Close()
	if err := db.Migrate(database); err != nil {
		slog.Error("migrations failed", "err", err)
		os.Exit(1)
	}
	st := store.New(database)
	ctx := context.Background()
	if _, err := st.SeedDefaultPlan(ctx); err != nil {
		slog.Error("plan seed failed", "err", err)
		os.Exit(1)
	}
	expired, pastDue, suspended, err := st.ApplyDueTransitions(ctx, store.Now())
	if err != nil {
		slog.Error("transition run failed", "err", err)
		os.Exit(1)
	}
	slog.Info("billing sweep complete",
		"expired", expired, "past_due", pastDue, "suspended", suspended)
}
