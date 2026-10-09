// FoodPOS server entrypoint: config → db → migrate → plan catalog → routes → listen.
// Demo data lives in cmd/seed (dev only); tenants are provisioned with cmd/admin.
package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"foodpos/backend/internal/api"
	"foodpos/backend/internal/auth"
	"foodpos/backend/internal/config"
	"foodpos/backend/internal/db"
	"foodpos/backend/internal/notify"
	"foodpos/backend/internal/store"
	"foodpos/backend/internal/ws"
)

func main() {
	cfg := config.Load()
	if err := cfg.Validate(); err != nil {
		slog.Error("invalid config", "err", err)
		os.Exit(1)
	}
	if cfg.Env == "production" && cfg.SMTPHost == "" {
		slog.Warn("SMTP not configured; password reset and renewal e-mail are unavailable")
	}
	slog.Info("foodpos server starting", "port", cfg.Port, "env", cfg.Env, "dev", cfg.Dev)

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
	authMgr := auth.New(cfg.JWTSecret, cfg.BcryptCost)

	// Every deployment needs the plan catalog (registration + billing).
	if err := st.SeedDefaultPlans(context.Background()); err != nil {
		slog.Error("plan catalog setup failed", "err", err)
		os.Exit(1)
	}

	// Platform superadmin from env (created once on first boot).
	if err := ensureSuperAdmin(st, authMgr); err != nil {
		slog.Error("superadmin setup failed", "err", err)
		os.Exit(1)
	}
	hub := ws.NewHub(authMgr)
	tickets := auth.NewTicketStore(auth.SSETicketTTL)
	hub.SetTicketStore(tickets)

	notifier, err := notify.NewFCMNotifier(cfg.FCMCredentials)
	if err != nil {
		slog.Error("fcm setup failed", "err", err)
		os.Exit(1)
	}

	srv := &api.Server{
		Store:     st,
		Auth:      authMgr,
		Hub:       hub,
		Tickets:   tickets,
		Cfg:       cfg,
		UploadDir: cfg.UploadDir,
		Notifier:  notifier,
	}

	httpSrv := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           srv.Routes(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	go func() {
		slog.Info("listening", "addr", httpSrv.Addr)
		if err := httpSrv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("listen failed", "err", err)
			os.Exit(1)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop
	slog.Info("shutting down")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = httpSrv.Shutdown(ctx)
}

// ensureSuperAdmin creates the platform admin from FOODPOS_SUPERADMIN_EMAIL /
// FOODPOS_SUPERADMIN_PASSWORD on first boot (idempotent).
func ensureSuperAdmin(st *store.Store, mgr *auth.Manager) error {
	email := strings.ToLower(strings.TrimSpace(os.Getenv("FOODPOS_SUPERADMIN_EMAIL")))
	pw := os.Getenv("FOODPOS_SUPERADMIN_PASSWORD")
	if email == "" || pw == "" {
		return nil
	}
	if _, err := st.GetPlatformAdminByEmail(context.Background(), email); err == nil {
		return nil
	}
	hash, err := mgr.HashPassword(pw)
	if err != nil {
		return err
	}
	_, err = st.CreatePlatformAdmin(context.Background(), "Superadmin", email, hash)
	return err
}
