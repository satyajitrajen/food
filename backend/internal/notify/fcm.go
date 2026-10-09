// Package notify sends push notifications through the FCM HTTP v1 API.
//
// Credentials are a Google service-account JSON file (FOODPOS_FCM_CREDENTIALS);
// the project id comes from that file. Without credentials the notifier is a
// silent no-op, so dev/test servers never try to reach Google.
package notify

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"time"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
)

const (
	fcmScope       = "https://www.googleapis.com/auth/firebase.messaging"
	defaultBaseURL = "https://fcm.googleapis.com"
)

// FCMNotifier sends notifications to device registration tokens.
type FCMNotifier struct {
	client    *http.Client
	projectID string
	baseURL   string
}

// NewFCMNotifier loads a service-account JSON from credentialsPath. An empty
// path returns a disabled notifier (every send is a no-op).
func NewFCMNotifier(credentialsPath string) (*FCMNotifier, error) {
	if strings.TrimSpace(credentialsPath) == "" {
		return &FCMNotifier{}, nil
	}
	raw, err := os.ReadFile(credentialsPath)
	if err != nil {
		return nil, fmt.Errorf("read fcm credentials: %w", err)
	}
	creds, err := google.CredentialsFromJSON(context.Background(), raw, fcmScope)
	if err != nil {
		return nil, fmt.Errorf("parse fcm credentials: %w", err)
	}
	if creds.ProjectID == "" {
		return nil, fmt.Errorf("fcm credentials have no project_id")
	}
	hc := oauth2.NewClient(context.Background(), creds.TokenSource)
	hc.Timeout = 10 * time.Second
	return New(hc, creds.ProjectID, defaultBaseURL), nil
}

// New builds a notifier around an already-authorised HTTP client (tests pass
// a plain client and an httptest base URL).
func New(client *http.Client, projectID, baseURL string) *FCMNotifier {
	if baseURL == "" {
		baseURL = defaultBaseURL
	}
	return &FCMNotifier{client: client, projectID: projectID, baseURL: strings.TrimRight(baseURL, "/")}
}

// Enabled reports whether sends actually go out.
func (f *FCMNotifier) Enabled() bool { return f != nil && f.client != nil && f.projectID != "" }

type v1Message struct {
	Message struct {
		Token        string            `json:"token"`
		Notification v1Notification    `json:"notification"`
		Data         map[string]string `json:"data,omitempty"`
		Android      map[string]any    `json:"android,omitempty"`
	} `json:"message"`
}

type v1Notification struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}

// SendToTokens delivers one message per token (HTTP v1 has no multicast).
// Returns the number of successful sends; failures are logged, never fatal.
func (f *FCMNotifier) SendToTokens(ctx context.Context, tokens []string, title, body string, data map[string]string) int {
	if !f.Enabled() {
		return 0
	}
	sent := 0
	for _, tok := range tokens {
		if tok == "" {
			continue
		}
		if err := f.sendOne(ctx, tok, title, body, data); err != nil {
			slog.Warn("fcm send failed", "err", err)
			continue
		}
		sent++
	}
	return sent
}

func (f *FCMNotifier) sendOne(ctx context.Context, token, title, body string, data map[string]string) error {
	var m v1Message
	m.Message.Token = token
	m.Message.Notification = v1Notification{Title: title, Body: body}
	m.Message.Data = data
	m.Message.Android = map[string]any{"priority": "high"}
	payload, err := json.Marshal(m)
	if err != nil {
		return err
	}
	url := f.baseURL + "/v1/projects/" + f.projectID + "/messages:send"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	res, err := f.client.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode >= 300 {
		msg, _ := io.ReadAll(io.LimitReader(res.Body, 512))
		return fmt.Errorf("fcm status %d: %s", res.StatusCode, strings.TrimSpace(string(msg)))
	}
	return nil
}
