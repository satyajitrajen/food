// Package ws: an outlet-scoped pub/sub hub for realtime events (KOT updates,
// table changes, shift events). Clients connect to /ws?outlet_id=…&token=….
// Each event carries an SSE `id:` line (per-outlet sequence); on reconnect the
// client sends last_event_id and the hub replays anything newer from its
// in-memory ring (single-instance assumption — documented in the runbook).
package ws

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"strconv"
	"sync"
	"time"

	"foodpos/backend/internal/auth"
	"foodpos/backend/internal/httpx"
)

const historyCap = 1000

type Event struct {
	Type      string          `json:"type"` // kot.created|kot.updated|table.updated|order.updated|shift.updated
	OutletID  string          `json:"outlet_id"`
	Payload   json.RawMessage `json:"payload"`
	Timestamp time.Time       `json:"ts"`
	seq       uint64          // per-outlet sequence (SSE id; not serialized)
}

type client struct {
	outletID string
	ch       chan Event
}

// Hub broadcasts events to all clients of an outlet and keeps a per-outlet
// replay ring so reconnecting terminals don't miss anything.
type Hub struct {
	mu       sync.Mutex
	clients  map[*client]struct{}
	history  map[string][]Event
	counters map[string]uint64
	authMgr  *auth.Manager
	tickets  *auth.TicketStore
}

func NewHub(authMgr *auth.Manager) *Hub {
	return &Hub{
		clients:  map[*client]struct{}{},
		history:  map[string][]Event{},
		counters: map[string]uint64{},
		authMgr:  authMgr,
	}
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

// Publish sequences, archives and broadcasts an event to every outlet client.
func (h *Hub) Publish(evt Event) {
	h.mu.Lock()
	defer h.mu.Unlock()
	evt.seq = h.counters[evt.OutletID] + 1
	h.counters[evt.OutletID] = evt.seq
	h.history[evt.OutletID] = append(h.history[evt.OutletID], evt)
	if n := len(h.history[evt.OutletID]); n > historyCap {
		h.history[evt.OutletID] = h.history[evt.OutletID][n-historyCap:]
	}
	for c := range h.clients {
		if c.outletID == evt.OutletID || evt.OutletID == "" {
			select {
			case c.ch <- evt:
			default: // slow consumer: drop (replay covers reconnects)
			}
		}
	}
}

// recentSince returns events of an outlet newer than seq (for replay).
func (h *Hub) recentSince(outletID string, after uint64) []Event {
	h.mu.Lock()
	defer h.mu.Unlock()
	hist := h.history[outletID]
	var out []Event
	for _, e := range hist {
		if e.seq > after {
			out = append(out, e)
		}
	}
	return out
}

func writeSSE(w http.ResponseWriter, evt Event) {
	body, err := json.Marshal(evt)
	if err != nil {
		return
	}
	_, _ = fmt.Fprintf(w, "id: %d\ndata: %s\n\n", evt.seq, body)
}

// Handler upgrades to SSE-style plain streaming (no external ws dep needed).
func (h *Hub) Handler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()
		outletID := q.Get("outlet_id")
		token := q.Get("token")
		var claims *auth.Claims
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

		var last uint64
		if raw := q.Get("last_event_id"); raw != "" {
			if n, err := strconv.ParseUint(raw, 10, 64); err == nil {
				last = n
			}
		}

		c := h.Subscribe(outletID)
		defer h.Unsubscribe(c)
		slog.Info("ws client connected", "outlet", outletID, "staff", claims.ActorID, "last_event_id", last)

		// Replay everything newer than the client's last id before going live.
		for _, evt := range h.recentSince(outletID, last) {
			writeSSE(w, evt)
		}
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
				writeSSE(w, evt)
				fl.Flush()
			case <-context.Background().Done():
				return
			}
		}
	}
}
