// Package leadfwd forwards landing leads and trial sign-ups to the Nexory
// website's admin (POST /api/leads/ingest), so sales sees every Hishobkr form
// in one place. It is fire-and-forget: the customer's request never waits on
// it or fails because of it. Disabled unless both env vars are set:
//
//	FOODPOS_LEAD_FORWARD_URL     e.g. http://127.0.0.1:8082/api/leads/ingest/
//	FOODPOS_LEAD_FORWARD_SECRET  shared with nexoryweb's LEAD_INGEST_SECRET
package leadfwd

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"time"
)

// Lead is the ingest payload. Kind is "demo", "contact" or "signup"; Ref is
// this backend's record id (the receiver dedupes on it).
type Lead struct {
	Kind      string `json:"kind"`
	Ref       string `json:"ref"`
	Name      string `json:"name,omitempty"`
	Company   string `json:"company,omitempty"`
	Email     string `json:"email,omitempty"`
	Phone     string `json:"phone,omitempty"`
	City      string `json:"city,omitempty"`
	Detail    string `json:"detail,omitempty"`
	CreatedAt string `json:"created_at,omitempty"`
}

var client = &http.Client{Timeout: 10 * time.Second}

// Enabled reports whether forwarding is configured.
func Enabled() bool {
	return os.Getenv("FOODPOS_LEAD_FORWARD_URL") != "" && os.Getenv("FOODPOS_LEAD_FORWARD_SECRET") != ""
}

// Send posts one lead and returns any error (used by the backfill command).
func Send(ctx context.Context, l Lead, backfill bool) error {
	url, secret := os.Getenv("FOODPOS_LEAD_FORWARD_URL"), os.Getenv("FOODPOS_LEAD_FORWARD_SECRET")
	if url == "" || secret == "" {
		return fmt.Errorf("lead forwarding not configured")
	}
	body, err := json.Marshal(struct {
		Product string `json:"product"`
		Lead
	}{"hishobkr", l})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Ingest-Secret", secret)
	if backfill {
		req.Header.Set("X-Ingest-Backfill", "1")
	}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return fmt.Errorf("ingest returned %s", resp.Status)
	}
	return nil
}

// Forward sends a lead in the background, retrying briefly; failures are only logged.
func Forward(l Lead) {
	if !Enabled() {
		return
	}
	go func() {
		for attempt := 1; attempt <= 3; attempt++ {
			ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
			err := Send(ctx, l, false)
			cancel()
			if err == nil {
				return
			}
			slog.Warn("lead forward failed", "kind", l.Kind, "ref", l.Ref, "attempt", attempt, "err", err)
			time.Sleep(time.Duration(attempt*5) * time.Second)
		}
	}()
}
