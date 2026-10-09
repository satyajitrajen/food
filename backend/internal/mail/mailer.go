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

// Brand is the product name used in every outgoing mail.
const Brand = "Hishobkr"

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

// headerSafe strips CR/LF so user-supplied values (org names, addresses)
// can never inject extra headers.
func headerSafe(v string) string {
	return strings.NewReplacer("\r", " ", "\n", " ").Replace(v)
}

// Send delivers a plain-text e-mail.
func (s Sender) Send(to, subject, body string) error {
	to, subject = headerSafe(to), headerSafe(subject)
	msg := "From: " + headerSafe(s.from) + "\r\n" +
		"To: " + to + "\r\n" +
		"Subject: " + subject + "\r\n" +
		"MIME-Version: 1.0\r\n" +
		"Content-Type: text/plain; charset=utf-8\r\n\r\n" +
		strings.ReplaceAll(body, "\n", "\r\n")
	addr := fmt.Sprintf("%s:%d", s.host, s.port)
	auth := smtp.PlainAuth("", s.user, s.pass, s.host)
	if err := smtp.SendMail(addr, auth, envelopeAddr(s.from), []string{to}, []byte(msg)); err != nil {
		return err
	}
	slog.Info("mail sent", "subject", subject)
	return nil
}

// envelopeAddr extracts the bare address from "Name <addr>".
func envelopeAddr(from string) string {
	if i, j := strings.LastIndex(from, "<"), strings.LastIndex(from, ">"); i >= 0 && j > i {
		return from[i+1 : j]
	}
	return strings.TrimSpace(from)
}

func link(baseURL, path, token string) string {
	return strings.TrimRight(baseURL, "/") + path + "?token=" + token
}

// ---- body helpers (plain text) ----

func Welcome(name, orgName, baseURL, verifyToken string, trialDays int) string {
	trial := "Your subscription is active."
	if trialDays > 0 {
		trial = fmt.Sprintf("It is on a %d-day free trial.", trialDays)
	}
	return fmt.Sprintf(`Hello %s,

Welcome to %s! Your organization "%s" is ready. %s

Verify your e-mail address here:
%s

Your POS admin PIN was shown at registration. Add staff and outlets from
the owner console.

- The %s team`, name, Brand, orgName, trial, link(baseURL, "/console/verify", verifyToken), Brand)
}

func Reset(name, baseURL, token string) string {
	return fmt.Sprintf(`Hello %s,

Reset your %s password here:
%s

If you did not request this, you can ignore this e-mail.

- The %s team`, name, Brand, link(baseURL, "/console/reset", token), Brand)
}

// Receipt formats a payment receipt; grossPaise is the GST-inclusive amount
// in paise.
func Receipt(orgName, invoiceNo string, grossPaise int64, period string) string {
	return fmt.Sprintf(`Dear %s customer,

Thank you for your payment.

Invoice: %s
Amount paid: INR %d.%02d (incl. GST)
Period: %s

The invoice PDF is available in your owner console.

- %s`, orgName, invoiceNo, grossPaise/100, grossPaise%100, period, Brand)
}

func ExpiryReminder(orgName string, daysLeft int, baseURL string) string {
	return fmt.Sprintf(`Hello %s,

Your %s subscription %s. Renew to keep taking orders.

Manage your subscription here:
%s/console/billing

- The %s team`, orgName, Brand, daysLeftText(daysLeft), strings.TrimRight(baseURL, "/"), Brand)
}

func daysLeftText(d int) string {
	if d == 0 {
		return "expires today"
	}
	return fmt.Sprintf("expires in %d day(s)", d)
}
