package api

// Entitlement enforcement: paid writes (orders, KOT, shifts, expenses, menu,
// inventory, settings …) require an org whose subscription is trial or active.
// Reads stay available for data export. Offline terminals keep working during
// their grace window and learn about expiry on the next sync (server truth).

import (
	"net/http"

	"foodpos/backend/internal/auth"
	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/middleware"
)

func (s *Server) entitlementGate() func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			c, ok := middleware.ClaimsFrom(r.Context())
			if !ok {
				httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
				return
			}
			if c.Scope != auth.ScopeStaff {
				next.ServeHTTP(w, r)
				return
			}
			okEnt, err := s.Store.EntitlementOK(r.Context(), c.OrgID)
			if err != nil {
				httpx.ErrorJSON(w, r, httpx.NewError(500, "entitlement_check_failed", "Could not verify subscription"))
				return
			}
			if !okEnt {
				httpx.ErrorJSON(w, r, httpx.NewError(402, "subscription_expired",
					"Subscription is not active. Please renew to continue taking orders."))
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
