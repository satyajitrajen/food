package auth

import (
	"sync"
	"time"
)

// PIN lockout: a 4-6 digit PIN is brute-forceable, so each key (a staff id
// for login, the requesting actor for manager-PIN checks) gets MaxPINFails
// attempts; the next failure locks it for PINLockDuration. A success resets
// the counter. In-memory (single-instance assumption, like the SSE hub).

const (
	MaxPINFails     = 5
	PINLockDuration = 15 * time.Minute
)

type pinState struct {
	fails       int
	lockedUntil time.Time
	lastFail    time.Time
}

type PINLockout struct {
	mu    sync.Mutex
	state map[string]*pinState
	now   func() time.Time
}

func NewPINLockout() *PINLockout {
	return &PINLockout{state: map[string]*pinState{}, now: time.Now}
}

// Locked reports whether key is currently locked and until when.
func (l *PINLockout) Locked(key string) (bool, time.Time) {
	l.mu.Lock()
	defer l.mu.Unlock()
	st, ok := l.state[key]
	if !ok || !l.now().Before(st.lockedUntil) {
		return false, time.Time{}
	}
	return true, st.lockedUntil
}

// Fail records a failed attempt; it returns true when this failure locked key.
func (l *PINLockout) Fail(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	l.purgeLocked(now)
	st, ok := l.state[key]
	if !ok {
		st = &pinState{}
		l.state[key] = st
	}
	// A lock that has expired starts a fresh window.
	if !st.lockedUntil.IsZero() && !now.Before(st.lockedUntil) {
		st.fails, st.lockedUntil = 0, time.Time{}
	}
	st.fails++
	st.lastFail = now
	if st.fails >= MaxPINFails {
		st.lockedUntil = now.Add(PINLockDuration)
		st.fails = 0
		return true
	}
	return false
}

// Success clears key's failure history.
func (l *PINLockout) Success(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	delete(l.state, key)
}

// purgeLocked drops stale entries so the map cannot grow without bound.
func (l *PINLockout) purgeLocked(now time.Time) {
	if len(l.state) < 1024 {
		return
	}
	for k, st := range l.state {
		if now.After(st.lockedUntil) && now.Sub(st.lastFail) > PINLockDuration {
			delete(l.state, k)
		}
	}
}
