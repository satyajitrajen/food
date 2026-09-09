package middleware

// Scope-aware middleware for the SaaS tenant model:
//   - RequireScope gates a route group to one token scope (staff/owner/admin).
//   - StaffTenant enforces tenant binding for POS staff tokens: the outlet must
//     come from the claim, and any ?outlet_id query parameter must match it —
//     clients can no longer override the tenant by convention.

import (
	"net/http"

	"foodpos/backend/internal/auth"
	"foodpos/backend/internal/httpx"
)

func claims(w http.ResponseWriter, r *http.Request) *auth.Claims {
	c, ok := ClaimsFrom(r.Context())
	if !ok {
		httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
		return nil
	}
	return c
}

// RequireScope allows only tokens of the given scope through.
func RequireScope(scope string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			c := claims(w, r)
			if c == nil {
				return
			}
			if c.Scope != scope {
				httpx.ErrorJSON(w, r, httpx.ErrForbidden)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// StaffTenant binds a POS request to the staff member's org + outlet.
// Superadmin/owner scopes never reach POS routes (they are gated by
// RequireScope("staff") before this runs).
func StaffTenant() func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			c := claims(w, r)
			if c == nil {
				return
			}
			if c.Scope != auth.ScopeStaff {
				httpx.ErrorJSON(w, r, httpx.ErrForbidden)
				return
			}
			if c.OutletID == "" || c.OrgID == "" {
				httpx.ErrorJSON(w, r, httpx.NewError(403, "tenant_required", "Login is missing tenant scope"))
				return
			}
			if q := r.URL.Query().Get("outlet_id"); q != "" && q != c.OutletID {
				httpx.ErrorJSON(w, r, httpx.NewError(403, "tenant_mismatch", "Outlet does not belong to this session"))
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
