// Package middleware: request-id, recover, logging, JWT auth + roles.
package middleware

import (
	"context"
	"log/slog"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5/middleware"

	"foodpos/backend/internal/auth"
	"foodpos/backend/internal/httpx"
)

type ctxKey int

const claimsKey ctxKey = 1

// Auth validates the Bearer JWT and stores claims in context.
// Public routes are registered without this middleware.
func Auth(mgr *auth.Manager) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			header := r.Header.Get("Authorization")
			if header == "" {
				httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
				return
			}
			token := strings.TrimPrefix(header, "Bearer ")
			claims, err := mgr.Parse(token)
			if err != nil {
				httpx.ErrorJSON(w, r, err)
				return
			}
			next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), claimsKey, claims)))
		})
	}
}

// RequireRole gates a route to a minimum role.
func RequireRole(minRole string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			claims, ok := ClaimsFrom(r.Context())
			if !ok {
				httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
				return
			}
			if err := auth.RequireRole(claims, minRole); err != nil {
				httpx.ErrorJSON(w, r, err)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

func ClaimsFrom(ctx context.Context) (*auth.Claims, bool) {
	c, ok := ctx.Value(claimsKey).(*auth.Claims)
	return c, ok
}

// RequestID + Recover + Logger, re-exported for one-line wiring.
var (
	RequestID = middleware.RequestID
	Recoverer = middleware.Recoverer
)

func Logger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)
		next.ServeHTTP(ww, r)
		slog.Info("http",
			"method", r.Method, "path", r.URL.Path,
			"status", ww.Status(), "bytes", ww.BytesWritten(), "ms", 0)
	})
}
