package mail

// Minimal SMTP sender. When SMTP is not configured every Send logs instead of
// failing — callers use Enabled() to decide whether to fall back to echoing
// tokens in dev responses.

import (
	"fmt"
	"log/slog"
	"net/smtp"
	"strings"

	"foodpos/backend/internal/config"
)

type Sender struct {
	host string
	port int
	user string
	pass string
	from string
}

func New(cfg config.Config) Sender {
	return Sender{host: cfg.SMTPHost, port: cfg.SMTPPort, user: cfg.SMTPUser, pass: cfg.SMTPPass, from: cfg.SMTPFrom}
}

func (s Sender) Enabled() bool { return s.host != "" }

// Send delivers a plain-text e-mail.
func (s Sender) Send(to, subject, body string) error {
	msg := "From: " + s.from + "\r\n" +
		"To: " + to + "\r\n" +
		"Subject: " + subject + "\r\n" +
		"MIME-Version: 1.0\r\n" +
		"Content-Type: text/plain; charset=utf-8\r\n\r\n" +
		strings.ReplaceAll(body, "\n", "\r\n")
	addr := fmt.Sprintf("%s:%d", s.host, s.port)
	auth := smtp.PlainAuth("", s.user, s.pass, s.host)
	if err := smtp.SendMail(addr, auth, s.from, []string{to}, []byte(msg)); err != nil {
		return err
	}
	slog.Info("mail sent", "to", to, "subject", subject)
	return nil
}

// ---- body helpers (ASCII-safe plain text) ----

func Welcome(name, orgName, baseURL, verifyToken string) string {
	return fmt.Sprintf(`Hello %s,

Welcome to FoodPOS! Your organization "%s" is on a 14-day free trial.

Verify your e-mail address here:
%s/verify?token=%s

Your POS admin PIN was shown at registration and is also visible in the
console. Add staff and outlets from the owner dashboard.

- FoodPOS team`, name, orgName, baseURL, verifyToken)
}

func Reset(name, baseURL, token string) string {
	return fmt.Sprintf(`Hello %s,

Reset your FoodPOS password here:
%s/reset?token=%s

If you did not request this, you can ignore this e-mail.

- FoodPOS team`, name, baseURL, token)
}

func Receipt(orgName, invoiceNo string, gross int64, period string) string {
	return fmt.Sprintf(`Dear %s customer,

Thank you for your payment.

Invoice: %s
Amount paid: INR %d (incl. GST)
Period: %s

The invoice PDF is available in your account.

- FoodPOS`, orgName, invoiceNo, gross, period)
}

func ExpiryReminder(orgName string, daysLeft int, baseURL string) string {
	return fmt.Sprintf(`Hello %s,

Your FoodPOS subscription %s. Renew to keep taking orders.

Manage your subscription here:
%s/org/billing

- FoodPOS team`, orgName, daysLeftText(daysLeft), baseURL)
}

func daysLeftText(d int) string {
	if d == 0 {
		return "expires today"
	}
	return fmt.Sprintf("expires in %d day(s)", d)
}
