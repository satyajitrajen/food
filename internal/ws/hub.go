// Package ws: an outlet-scoped pub/sub hub for realtime events (KOT updates,
// table changes, shift events). Clients connect to /ws?outlet_id=…&token=….
package ws

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"sync"
	"time"


	"foodpos/backend/internal/auth"
	"foodpos/backend/internal/httpx"
)

type Event struct {
	Type      string          `json:"type"` // kot.created|kot.updated|table.updated|order.updated|shift.updated
	OutletID  string          `json:"outlet_id"`
	Payload   json.RawMessage `json:"payload"`
	Timestamp time.Time       `json:"ts"`
}

type client struct {
	outletID string
	ch       chan Event
}

// Hub broadcasts events to all clients of an outlet.
type Hub struct {
	mu      sync.RWMutex
	clients map[*client]struct{}
	authMgr *auth.Manager
	tickets *auth.TicketStore
}

func NewHub(authMgr *auth.Manager) *Hub {
	return &Hub{clients: map[*client]struct{}{}, authMgr: authMgr}
}

// SetTicketStore wires the single-use SSE ticket store (preferred auth for
// the query-param connect; the raw JWT param stays as a legacy fallback).
func (h *Hub) SetTicketStore(ts *auth.TicketStore) { h.tickets = ts }

func (h *Hub) Subscribe(outletID string) *client {
	c := &client{outletID: outletID, ch: make(chan Event, 64)}
	h.mu.Lock()
	h.clients[c] = struct{}{}
	h.mu.Unlock()
	return c
}

func (h *Hub) Unsubscribe(c *client) {
	h.mu.Lock()
	delete(h.clients, c)
	h.mu.Unlock()
	close(c.ch)
}

// Publish sends an event to every subscriber of the outlet (non-blocking).
func (h *Hub) Publish(evt Event) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	for c := range h.clients {
		if c.outletID == evt.OutletID || evt.OutletID == "" {
			select {
			case c.ch <- evt:
			default: // slow consumer: drop
			}
		}
	}
}

// Handler upgrades to SSE-style plain streaming (no external ws dep needed):
// we serve server-sent events over GET /ws which is simpler and robust for
// POS terminals; the Flutter side consumes via EventSource/stream.
func (h *Hub) Handler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()
		outletID := q.Get("outlet_id")
		token := q.Get("token")
		var claims *auth.Claims
		// Preferred: single-use connect ticket (nothing reusable in the logs).
		if ts := h.tickets; ts != nil {
			if c, ok := ts.Consume(q.Get("ticket")); ok {
				claims = c
			}
		}
		if claims == nil {
			c, err := h.authMgr.Parse(token)
			if err != nil {
				httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
				return
			}
			claims = c
		}
		if outletID == "" {
			outletID = claims.OutletID
		}

		fl, ok := w.(http.Flusher)
		if !ok {
			httpx.ErrorJSON(w, r, httpx.NewError(500, "stream_unsupported", "Streaming unsupported"))
			return
		}
		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("Connection", "keep-alive")

		c := h.Subscribe(outletID)
		defer h.Unsubscribe(c)
		slog.Info("ws client connected", "outlet", outletID, "staff", claims.StaffID)

		// Initial comment so clients detect the stream opened.
		_, _ = w.Write([]byte(": connected\n\n"))
		fl.Flush()

		keepAlive := time.NewTicker(20 * time.Second)
		defer keepAlive.Stop()

		for {
			select {
			case <-r.Context().Done():
				return
			case <-keepAlive.C:
				_, _ = w.Write([]byte(": ping\n\n"))
				fl.Flush()
			case evt := <-c.ch:
				body, err := json.Marshal(evt)
				if err != nil {
					continue
				}
				_, _ = w.Write([]byte("data: " + string(body) + "\n\n"))
				fl.Flush()
			case <-context.Background().Done():
				return
			}
		}
	}
}
