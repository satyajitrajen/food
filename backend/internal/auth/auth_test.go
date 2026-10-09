package auth

import (
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// Concurrent Issue/Consume must be data-race free (run with -race) and every
// ticket must be redeemable exactly once.
func TestTicketStoreConcurrentSingleUse(t *testing.T) {
	ts := NewTicketStore(time.Minute)
	claims := &Claims{Scope: ScopeStaff, ActorID: "st-1", OutletID: "out-1"}
	const n = 200
	tokens := make([]string, n)
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			tokens[i] = ts.Issue(claims)
		}(i)
	}
	wg.Wait()

	var redeemed int64
	for i := 0; i < n; i++ {
		for j := 0; j < 3; j++ { // three racers per ticket
			wg.Add(1)
			go func(tok string) {
				defer wg.Done()
				if c, ok := ts.Consume(tok); ok && c.ActorID == "st-1" {
					atomic.AddInt64(&redeemed, 1)
				}
			}(tokens[i])
		}
	}
	wg.Wait()
	if redeemed != n {
		t.Fatalf("redeemed %d tickets, want exactly %d (single use)", redeemed, n)
	}
}

func TestTicketStoreExpiry(t *testing.T) {
	ts := NewTicketStore(time.Millisecond)
	tok := ts.Issue(&Claims{ActorID: "x"})
	time.Sleep(5 * time.Millisecond)
	if _, ok := ts.Consume(tok); ok {
		t.Fatal("expired ticket must not be redeemable")
	}
}

func TestPINLockout(t *testing.T) {
	l := NewPINLockout()
	now := time.Date(2026, 10, 9, 12, 0, 0, 0, time.UTC)
	l.now = func() time.Time { return now }
	for i := 1; i < MaxPINFails; i++ {
		if l.Fail("st-1") {
			t.Fatalf("locked after %d fails, want %d", i, MaxPINFails)
		}
	}
	if !l.Fail("st-1") {
		t.Fatal("5th failure must lock")
	}
	if locked, _ := l.Locked("st-1"); !locked {
		t.Fatal("expected st-1 locked")
	}
	if locked, _ := l.Locked("st-2"); locked {
		t.Fatal("lockout must be per key")
	}
	now = now.Add(PINLockDuration + time.Second)
	if locked, _ := l.Locked("st-1"); locked {
		t.Fatal("lock should expire after the window")
	}
	l.Fail("st-1")
	l.Success("st-1")
	for i := 1; i < MaxPINFails; i++ {
		if l.Fail("st-1") {
			t.Fatal("success must reset the failure count")
		}
	}
}
