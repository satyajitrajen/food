package middleware

// CORS middleware for the owner/superadmin web console. Configurable via
// FOODPOS_CORS_ORIGINS: "*" (default) allows any origin — bearer JWTs are the
// real gate; a comma-separated list restricts to specific origins; empty
// disables CORS entirely (same-origin reverse proxy).

import (
	"net/http"
	"strings"
)

func CORS(origins string) func(http.Handler) http.Handler {
	allowAll := origins == "*"
	var allowed map[string]bool
	if !allowAll && strings.TrimSpace(origins) != "" {
		allowed = map[string]bool{}
		for _, o := range strings.Split(origins, ",") {
			if o = strings.TrimSpace(o); o != "" {
				allowed[o] = true
			}
		}
	}

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			origin := r.Header.Get("Origin")
			if origin != "" {
				ok := allowAll || (allowed != nil && allowed[origin])
				if ok {
					h := w.Header()
					if allowAll {
						h.Set("Access-Control-Allow-Origin", "*")
					} else {
						h.Set("Access-Control-Allow-Origin", origin)
						h.Set("Vary", "Origin")
					}
					h.Set("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS")
					h.Set("Access-Control-Allow-Headers", "Content-Type, Authorization, Idempotency-Key")
					h.Set("Access-Control-Max-Age", "600")
				}
				if r.Method == http.MethodOptions {
					w.WriteHeader(http.StatusNoContent)
					return
				}
			}
			next.ServeHTTP(w, r)
		})
	}
}
