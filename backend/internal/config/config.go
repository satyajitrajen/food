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
	BcryptCost int
	UploadDir  string

	// Env is the deployment environment label ("development" default,
	// "production"). Security never depends on it alone: see Dev.
	Env string
	// Dev enables developer conveniences (echoing password-reset tokens when
	// SMTP is off, the built-in dev JWT secret). Off unless FOODPOS_DEV=1 and
	// never on when FOODPOS_ENV=production.
	Dev bool

	// SaaS billing + security.
	LicenseSecret         string // HMAC for signed offline entitlements (fallback JWTSecret)
	RazorpayKey           string
	RazorpaySecret        string
	RazorpayWebhookSecret string
	// Razorpay subscription (auto-renew) knobs.
	RazorpayCurrency string
	RazorpayBaseURL  string

	// Outbound e-mail (SMTP). When SMTPHost is empty mail calls are logged only.
	SMTPHost string
	SMTPPort int
	SMTPUser string
	SMTPPass string
	SMTPFrom string
	// AppBaseURL is the console/portal origin used in mail links.
	AppBaseURL string
	// CORSOrigins: empty (default) disables CORS (same-origin reverse
	// proxy); a comma-separated list allows those origins; '*' any origin.
	CORSOrigins string

	// FCMCredentials is the path of a Google service-account JSON for FCM
	// HTTP v1 push. Empty = push disabled (silent no-op).
	FCMCredentials string
}

// DevJWTSecret is the built-in secret; accepted only when Dev is on.
const DevJWTSecret = "dev-secret-change-me"

func Load() Config {
	envName := env("FOODPOS_ENV", "development")
	dev := os.Getenv("FOODPOS_DEV") == "1" && envName != "production"
	jwtSecret := os.Getenv("FOODPOS_JWT_SECRET")
	if jwtSecret == "" && dev {
		jwtSecret = DevJWTSecret
	}
	return Config{
		Port:       env("FOODPOS_PORT", "8080"),
		DSN:        env("FOODPOS_DSN", ""),
		JWTSecret:  jwtSecret,
		BcryptCost: envInt("FOODPOS_BCRYPT_COST", 10),
		UploadDir:  env("FOODPOS_UPLOAD_DIR", "./uploads"),
		Env:        envName,
		Dev:        dev,

		LicenseSecret:         env("FOODPOS_LICENSE_SECRET", ""),
		RazorpayKey:           env("FOODPOS_RAZORPAY_KEY_ID", ""),
		RazorpaySecret:        env("FOODPOS_RAZORPAY_KEY_SECRET", ""),
		RazorpayWebhookSecret: env("FOODPOS_RAZORPAY_WEBHOOK_SECRET", ""),

		RazorpayCurrency: env("FOODPOS_RAZORPAY_CURRENCY", "INR"),
		RazorpayBaseURL:  env("FOODPOS_RAZORPAY_BASE_URL", "https://api.razorpay.com"),

		SMTPHost:    env("FOODPOS_SMTP_HOST", ""),
		SMTPPort:    envInt("FOODPOS_SMTP_PORT", 587),
		SMTPUser:    env("FOODPOS_SMTP_USER", ""),
		SMTPPass:    env("FOODPOS_SMTP_PASS", ""),
		SMTPFrom:    env("FOODPOS_SMTP_FROM", "Hishobkr <no-reply@hishobkr.com>"),
		AppBaseURL:  env("FOODPOS_APP_BASE_URL", "https://food.nexorytechnologies.com"),
		CORSOrigins: os.Getenv("FOODPOS_CORS_ORIGINS"),

		FCMCredentials: os.Getenv("FOODPOS_FCM_CREDENTIALS"),
	}
}

// Validate rejects configurations that are unsafe to boot: outside explicit
// dev mode (FOODPOS_DEV=1) the JWT secret must be set and not the dev default.
func (c Config) Validate() error {
	if c.Dev {
		return nil
	}
	if c.JWTSecret == "" || c.JWTSecret == DevJWTSecret {
		return fmt.Errorf("FOODPOS_JWT_SECRET must be set to a strong secret (or run with FOODPOS_DEV=1 for local development)")
	}
	if len(c.JWTSecret) < 16 {
		return fmt.Errorf("FOODPOS_JWT_SECRET must be at least 16 characters")
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

func envInt64(key string, def int64) int64 {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil {
			return n
		}
	}
	return def
}
