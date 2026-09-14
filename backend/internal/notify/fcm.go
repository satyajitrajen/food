package notify

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"time"
)

// FCMNotifier sends push notifications via Firebase Cloud Messaging.
type FCMNotifier struct {
	client    *http.Client
	projectID string
	serverKey string
}

func NewFCMNotifier(projectID, serverKey string) *FCMNotifier {
	return &FCMNotifier{
		client:    &http.Client{Timeout: 10 * time.Second},
		projectID: projectID,
		serverKey: serverKey,
	}
}

// PushPayload defines the FCM HTTP notification payload.
type PushPayload struct {
	To               string            `json:"to,omitempty"`
	RegistrationIDs  []string          `json:"registration_ids,omitempty"`
	Notification     *NotificationData `json:"notification,omitempty"`
	Data             map[string]any    `json:"data,omitempty"`
	Priority         string            `json:"priority"`
	ContentAvailable bool              `json:"content_available"`
}

type NotificationData struct {
	Title string `json:"title"`
	Body  string `json:"body"`
	Sound string `json:"sound"`
}

// SendToTokens sends push notifications to a slice of device registration tokens.
func (f *FCMNotifier) SendToTokens(ctx context.Context, tokens []string, title, body string, data map[string]any) error {
	if len(tokens) == 0 {
		return nil
	}
	payload := PushPayload{
		RegistrationIDs: tokens,
		Notification: &NotificationData{
			Title: title,
			Body:  body,
			Sound: "default",
		},
		Data:             data,
		Priority:         "high",
		ContentAvailable: true,
	}
	return f.send(ctx, payload)
}

// SendToTopic sends a push notification to an FCM topic (e.g. /topics/outlet_out-01 or /topics/hishobkr_orders).
func (f *FCMNotifier) SendToTopic(ctx context.Context, topic, title, body string, data map[string]any) error {
	if topic == "" {
		return nil
	}
	if topic[0] != '/' {
		topic = "/topics/" + topic
	}
	payload := PushPayload{
		To: topic,
		Notification: &NotificationData{
			Title: title,
			Body:  body,
			Sound: "default",
		},
		Data:             data,
		Priority:         "high",
		ContentAvailable: true,
	}
	return f.send(ctx, payload)
}

func (f *FCMNotifier) send(ctx context.Context, payload PushPayload) error {
	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal fcm payload: %w", err)
	}

	// In development or when no server key is configured, log the notification.
	if f.serverKey == "" {
		slog.Info("[FCM] Push dispatched (dry-run/dev)",
			"to", payload.To,
			"token_count", len(payload.RegistrationIDs),
			"title", payload.Notification.Title,
			"body", payload.Notification.Body,
			"data", payload.Data,
		)
		return nil
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://fcm.googleapis.com/fcm/send", bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("create fcm request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "key="+f.serverKey)

	res, err := f.client.Do(req)
	if err != nil {
		slog.Warn("[FCM] Push request failed", "err", err)
		return err
	}
	defer res.Body.Close()

	if res.StatusCode >= 400 {
		slog.Warn("[FCM] Push server rejected request", "status", res.StatusCode)
		return fmt.Errorf("fcm rejected with status %d", res.StatusCode)
	}

	slog.Info("[FCM] Push successfully delivered", "status", res.StatusCode)
	return nil
}
