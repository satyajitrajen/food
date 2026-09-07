// Package middleware: request-id, recover, logging, JWT auth + roles.
package middleware

import (
	"net"
	"net/http"
	"strconv"
	"sync"
	"time"

	"foodpos/backend/internal/httpx"
)

type rateWindow struct {
	start time.Time
	count int
}

// RateLimiter is a fixed-window per-IP limiter for the auth endpoints.
type RateLimiter struct {
	mu     sync.Mutex
	limit  int
	window time.Duration
	hits   map[string]*rateWindow
}

func NewRateLimiter(limit int, window time.Duration) *RateLimiter {
	return &RateLimiter{limit: limit, window: window, hits: map[string]*rateWindow{}}
}

func (rl *RateLimiter) Allow(key string, now time.Time) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()
	w, ok := rl.hits[key]
	if !ok || now.Sub(w.start) >= rl.window {
		rl.hits[key] = &rateWindow{start: now, count: 1}
		return true
	}
	w.count++
	return w.count <= rl.limit
}

// RateLimit returns middleware that rejects excess requests with 429.
func RateLimit(limit int, window time.Duration) func(http.Handler) http.Handler {
	rl := NewRateLimiter(limit, window)
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ip, _, err := net.SplitHostPort(r.RemoteAddr)
			if err != nil {
				ip = r.RemoteAddr
			}
			if !rl.Allow(ip, time.Now()) {
				w.Header().Set("Retry-After", strconv.Itoa(int(window.Seconds())))
				httpx.ErrorJSON(w, r, httpx.NewError(http.StatusTooManyRequests, "rate_limited",
					"Too many requests; slow down and retry later"))
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
