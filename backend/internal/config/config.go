package config

import (
	"fmt"
	"os"
	"strconv"
)

type Config struct {
	Port       string
	DSN        string
	JWTSecret  string
	Seed       bool
	BcryptCost int
	UploadDir  string

	// Env is the deployment environment: "development" (default) or
	// "production". Production flips the secure defaults on: the JWT secret
	// becomes mandatory and wildcard CORS is dropped.
	Env string
	// Dev enables developer conveniences (e.g. echoing password-reset tokens
	// when SMTP is off). Default true outside production; override with
	// FOODPOS_DEV=1 (on) or FOODPOS_DEV=0 (off).
	Dev bool

	// SaaS billing + security.
	LicenseSecret         string // HMAC for signed offline entitlements (fallback JWTSecret)
	RazorpayKey           string
	RazorpaySecret        string
	RazorpayWebhookSecret string

	// Outbound e-mail (SMTP). When SMTPHost is empty mail calls are logged only.
	SMTPHost string
	SMTPPort int
	SMTPUser string
	SMTPPass string
	SMTPFrom string
	// AppBaseURL is the console/portal origin used in mail links.
	AppBaseURL string
	// CORSOrigins: '*' allows any origin (default — bearer tokens protect the
	// API); a comma-separated list restricts to specific origins; empty disables
	// CORS (use a same-origin reverse proxy).
	CORSOrigins string
}

func Load() Config {
	envName := env("FOODPOS_ENV", "development")
	dev := false
	switch {
	case os.Getenv("FOODPOS_DEV") != "":
		dev = os.Getenv("FOODPOS_DEV") == "1"
	case envName != "production":
		dev = true
	}
	cors := env("FOODPOS_CORS_ORIGINS", "*")
	if envName == "production" && cors == "*" {
		// Same-origin reverse proxy instead of an open wildcard.
		cors = ""
	}
	return Config{
		Port:       env("FOODPOS_PORT", "8080"),
		DSN:        env("FOODPOS_DSN", ""),
		JWTSecret:  env("FOODPOS_JWT_SECRET", "dev-secret-change-me"),
		Seed:       env("FOODPOS_SEED", "0") == "1",
		BcryptCost: envInt("FOODPOS_BCRYPT_COST", 10),
		UploadDir:  env("FOODPOS_UPLOAD_DIR", "./uploads"),
		Env:        envName,
		Dev:        dev,

		LicenseSecret:         env("FOODPOS_LICENSE_SECRET", ""),
		RazorpayKey:           env("FOODPOS_RAZORPAY_KEY_ID", ""),
		RazorpaySecret:        env("FOODPOS_RAZORPAY_KEY_SECRET", ""),
		RazorpayWebhookSecret: env("FOODPOS_RAZORPAY_WEBHOOK_SECRET", ""),

		SMTPHost:    env("FOODPOS_SMTP_HOST", ""),
		SMTPPort:    envInt("FOODPOS_SMTP_PORT", 587),
		SMTPUser:    env("FOODPOS_SMTP_USER", ""),
		SMTPPass:    env("FOODPOS_SMTP_PASS", ""),
		SMTPFrom:    env("FOODPOS_SMTP_FROM", "FoodPOS <no-reply@foodpos.app>"),
		AppBaseURL:  env("FOODPOS_APP_BASE_URL", "https://app.foodpos.example"),
		CORSOrigins: cors,
	}
}

// Validate rejects configurations that are unsafe to boot in production.
func (c Config) Validate() error {
	if c.Env != "production" {
		return nil
	}
	if c.JWTSecret == "" || c.JWTSecret == "dev-secret-change-me" {
		return fmt.Errorf("FOODPOS_JWT_SECRET must be set to a strong secret when FOODPOS_ENV=production")
	}
	return nil
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func envInt(key string, def int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}
