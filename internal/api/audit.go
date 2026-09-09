package api

// Write-audit middleware: every POS write that passes the entitlement gate is
// recorded in audit_log with org/outlet attribution (columns added in 006).

import (
	"net/http"

	"foodpos/backend/internal/auth"
	"foodpos/backend/internal/middleware"
	"foodpos/backend/internal/store"
)

func (s *Server) auditMiddleware() func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			next.ServeHTTP(w, r)
			// Best-effort after the handler so failures don't double-record.
			c, ok := middleware.ClaimsFrom(r.Context())
			if !ok || c.Scope != auth.ScopeStaff {
				return
			}
			outletID := c.OutletID
			if q := r.URL.Query().Get("outlet_id"); q != "" {
				outletID = q
			}
			_ = s.Store.Audit(r.Context(), c.OrgID, outletID, c.ActorID,
				"write."+r.Method, r.URL.Path, "",
				store.MetaJSON(map[string]any{"staff": c.Name}))
		})
	}
}
