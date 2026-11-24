package ws

import (
	"bufio"
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"foodpos/backend/internal/auth"
)

// streamEvents opens the stream with the given query, reads until the
// ": connected" marker (written after any replay) and returns the event
// lines seen before it.
func streamEvents(t *testing.T, h *Hub, ts *auth.TicketStore, extra string) []string {
	t.Helper()
	ticket := ts.Issue(&auth.Claims{Scope: auth.ScopeStaff, ActorID: "st-1", OutletID: "out-1"})
	srv := httptest.NewServer(h.Handler())
	defer srv.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	req, _ := http.NewRequestWithContext(ctx, "GET", srv.URL+"?ticket="+ticket+extra, nil)
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	var events []string
	sc := bufio.NewScanner(res.Body)
	for sc.Scan() {
		line := sc.Text()
		if strings.HasPrefix(line, ": connected") {
			return events
		}
		if strings.HasPrefix(line, "data: ") {
			events = append(events, line)
		}
	}
	t.Fatalf("stream ended before connected marker: %v", sc.Err())
	return nil
}

// A fresh connection (no last_event_id) must not replay history: the client
// loads current state over REST, and replayed stale events (e.g. an old
// "KOT ready") would overwrite newer state. A reconnect still catches up.
func TestReplayOnlyOnReconnect(t *testing.T) {
	h := NewHub()
	ts := auth.NewTicketStore(time.Minute)
	h.SetTicketStore(ts)
	h.Publish(Event{Type: "kot.updated", OutletID: "out-1", Payload: []byte(`{"status":"ready"}`)})
	h.Publish(Event{Type: "kot.updated", OutletID: "out-1", Payload: []byte(`{"status":"served"}`)})

	if got := streamEvents(t, h, ts, ""); len(got) != 0 {
		t.Fatalf("fresh connect replayed %d events: %v", len(got), got)
	}
	if got := streamEvents(t, h, ts, "&last_event_id=1"); len(got) != 1 || !strings.Contains(got[0], "served") {
		t.Fatalf("reconnect after event 1 should replay only event 2, got %v", got)
	}
}
