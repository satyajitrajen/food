package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func reqWith(remote, xff string) *http.Request {
	r := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", nil)
	r.RemoteAddr = remote
	if xff != "" {
		r.Header.Set("X-Forwarded-For", xff)
	}
	return r
}

func TestClientIPFrom(t *testing.T) {
	cases := []struct {
		name, remote, xff, want string
	}{
		// A direct public client cannot spoof a faster bucket via XFF.
		{"public remote ignores XFF", "203.0.113.7:5555", "1.2.3.4", "203.0.113.7"},
		// Behind a loopback proxy (nginx on same host) the forwarded client wins.
		{"loopback proxy honors XFF", "127.0.0.1:9000", "198.51.100.9, 10.0.0.1", "198.51.100.9"},
		{"loopback proxy no XFF", "127.0.0.1:9000", "", "127.0.0.1"},
		// Docker bridge proxy.
		{"private proxy honors XFF", "172.17.0.5:9000", "198.51.100.9", "198.51.100.9"},
		{"loopback proxy empty XFF entry", "127.0.0.1:9000", "  ", "127.0.0.1"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := clientIPFrom(reqWith(tc.remote, tc.xff)); got != tc.want {
				t.Fatalf("clientIPFrom = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestRateLimitPerClient(t *testing.T) {
	rl := NewRateLimiter(2, time.Minute)
	now := time.Now()
	if !rl.Allow("1.1.1.1", now) || !rl.Allow("1.1.1.1", now) {
		t.Fatal("first two hits should pass")
	}
	if rl.Allow("1.1.1.1", now) {
		t.Fatal("third hit should be limited")
	}
	if !rl.Allow("2.2.2.2", now) {
		t.Fatal("other client should be unaffected")
	}
}
