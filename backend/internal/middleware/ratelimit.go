// Package middleware: request-id, recover, logging, JWT auth + roles.
package middleware

import (
	"net"
	"net/http"
	"strconv"
	"strings"
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

// clientIPFrom returns the client IP for rate-limit keys. X-Forwarded-For is
// honored only when the TCP peer is loopback/private (a reverse proxy on the
// same host or a docker bridge); a direct public client could otherwise spoof
// the header to rotate limit buckets.
func clientIPFrom(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	if isLocalNet(host) {
		if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
			if i := strings.IndexByte(xff, ','); i >= 0 {
				xff = xff[:i]
			}
			if ip := strings.TrimSpace(xff); ip != "" {
				return ip
			}
		}
	}
	return host
}

func isLocalNet(host string) bool {
	ip := net.ParseIP(host)
	return ip != nil && (ip.IsLoopback() || ip.IsPrivate())
}

// RateLimit returns middleware that rejects excess requests with 429.
func RateLimit(limit int, window time.Duration) func(http.Handler) http.Handler {
	rl := NewRateLimiter(limit, window)
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if !rl.Allow(clientIPFrom(r), time.Now()) {
				w.Header().Set("Retry-After", strconv.Itoa(int(window.Seconds())))
				httpx.ErrorJSON(w, r, httpx.NewError(http.StatusTooManyRequests, "rate_limited",
					"Too many requests; slow down and retry later"))
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
