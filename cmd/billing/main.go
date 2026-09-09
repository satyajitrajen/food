// Billing job: run daily (cron) to move subscriptions through their
// lifecycle (trial expiry, period end → past_due, grace → suspend) and to
// send renewal reminders when SMTP is configured. Reads the same env as the
// server. Reminders/e-mail hooks are log lines when SMTP is disabled.
package main

import (
	"context"
	"log/slog"
	"os"
	"time"

	"foodpos/backend/internal/config"
	"foodpos/backend/internal/db"
	"foodpos/backend/internal/mail"
	"foodpos/backend/internal/models"
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
	slog.Info("billing sweep complete", "expired", expired, "past_due", pastDue, "suspended", suspended)

	sendReminders(ctx, st)
}

// sendReminders e-mails orgs whose trial/period ends within 7 days.
func sendReminders(ctx context.Context, st *store.Store) {
	cfg := config.Load()
	sender := mail.New(cfg)
	if !sender.Enabled() {
		slog.Info("renewal reminders skipped (SMTP not configured)")
		return
	}
	subs, err := st.ListSubscriptions(ctx)
	if err != nil {
		slog.Error("list subscriptions failed", "err", err)
		return
	}
	now := time.Now().UTC()
	for _, sub := range subs {
		if sub.Status != models.SubTrial && sub.Status != models.SubActive {
			continue
		}
		end := time.Time{}
		if sub.Status == models.SubTrial && sub.TrialEndsAt != nil {
			end = *sub.TrialEndsAt
		}
		if sub.Status == models.SubActive && sub.CurrentPeriodEnd != nil {
			end = *sub.CurrentPeriodEnd
		}
		if end.IsZero() || !end.After(now) {
			continue
		}
		days := int(end.Sub(now).Hours()/24) + 1
		if days < 1 || days > 7 {
			continue
		}
		org, err := st.GetOrganization(ctx, sub.OrgID)
		if err != nil {
			continue
		}
		if err := sender.Send(org.Email, "Your FoodPOS subscription", mail.ExpiryReminder(org.Name, days, cfg.AppBaseURL)); err != nil {
			slog.Warn("reminder failed", "org", sub.OrgID, "err", err)
			continue
		}
		_ = st.AddOrgEvent(ctx, sub.OrgID, "system", "sub.reminder_sent",
			store.MetaJSON(map[string]any{"days": days}))
		slog.Info("renewal reminder sent", "org", sub.OrgID, "days", days)
	}
}
