package config

import (
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
	return Config{
		Port:       env("FOODPOS_PORT", "8080"),
		DSN:        env("FOODPOS_DSN", ""),
		JWTSecret:  env("FOODPOS_JWT_SECRET", "dev-secret-change-me"),
		Seed:       env("FOODPOS_SEED", "0") == "1",
		BcryptCost: envInt("FOODPOS_BCRYPT_COST", 10),
		UploadDir:  env("FOODPOS_UPLOAD_DIR", "./uploads"),

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
		CORSOrigins: env("FOODPOS_CORS_ORIGINS", "*"),
	}
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
