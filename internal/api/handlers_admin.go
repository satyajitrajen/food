package api

// Platform (superadmin) APIs. Protected by RequireScope("admin") in the route
// table. Manual billing ops live here; the gateway adapter plugs in later.

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"foodpos/backend/internal/auth"
	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/models"
)

const adminSessionTTL = auth.RefreshTTL

func (s *Server) handleAdminLogin(w http.ResponseWriter, r *http.Request) {
	var req models.AdminLoginReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	req.Email = strings.ToLower(strings.TrimSpace(req.Email))
	admin, err := s.Store.GetPlatformAdminByEmail(r.Context(), req.Email)
	if err != nil || !s.Auth.CheckPassword(admin.PasswordHash, req.Password) {
		httpx.ErrorJSON(w, r, httpx.NewError(401, "bad_credentials", "Invalid email or password"))
		return
	}
	token, err := s.Auth.IssueAdminToken(admin.ID, admin.Name)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	refresh, hash := auth.NewRefreshToken()
	if err := s.Store.CreateSession(r.Context(), auth.ScopeAdmin, admin.ID, hash, time.Now().Add(adminSessionTTL)); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, models.AdminLoginResp{
		Token: token, RefreshToken: refresh, TokenType: "Bearer",
		ExpiresAt: time.Now().Add(auth.AccessTTL), Admin: admin.PlatformAdmin,
	})
}

func (s *Server) handleAdminRefresh(w http.ResponseWriter, r *http.Request) {
	var req refreshReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if req.RefreshToken == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_credentials", "refresh_token is required"))
		return
	}
	sess, err := s.Store.GetSession(r.Context(), auth.HashToken(req.RefreshToken))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if sess.Revoked || time.Now().After(sess.ExpiresAt) || sess.Scope != auth.ScopeAdmin {
		httpx.ErrorJSON(w, r, httpx.NewError(401, "invalid_refresh_token", "Refresh token is expired or revoked"))
		return
	}
	admin, err := s.Store.GetPlatformAdminByID(r.Context(), sess.ActorID)
	if err != nil {
		httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
		return
	}
	_ = s.Store.RevokeSession(r.Context(), sess.ID)
	token, err := s.Auth.IssueAdminToken(admin.ID, admin.Name)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	refresh, hash := auth.NewRefreshToken()
	if err := s.Store.CreateSession(r.Context(), auth.ScopeAdmin, admin.ID, hash, time.Now().Add(adminSessionTTL)); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, models.AdminLoginResp{
		Token: token, RefreshToken: refresh, TokenType: "Bearer",
		ExpiresAt: time.Now().Add(auth.AccessTTL), Admin: *admin,
	})
}

func (s *Server) handleAdminLogout(w http.ResponseWriter, r *http.Request) {
	var req refreshReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	sess, err := s.Store.GetSession(r.Context(), auth.HashToken(req.RefreshToken))
	if err == nil {
		_ = s.Store.RevokeSession(r.Context(), sess.ID)
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"revoked": true})
}

// handleListAdminOrgs lists organizations (filter by ?status=).
func (s *Server) handleListAdminOrgs(w http.ResponseWriter, r *http.Request) {
	status := r.URL.Query().Get("status")
	orgs, err := s.Store.ListOrganizations(r.Context(), status)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	subs, err := s.Store.ListSubscriptions(r.Context())
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	byOrg := map[string]models.OrgSubscription{}
	for _, sub := range subs {
		byOrg[sub.OrgID] = sub
	}
	type row struct {
		Organization models.Organization     `json:"organization"`
		Subscription *models.OrgSubscription `json:"subscription"`
	}
	out := make([]row, 0, len(orgs))
	for _, org := range orgs {
		var sub *models.OrgSubscription
		if v, ok := byOrg[org.ID]; ok {
			sub = &v
		}
		out = append(out, row{Organization: org, Subscription: sub})
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"organizations": out})
}

func (s *Server) handleAdminOrgDetail(w http.ResponseWriter, r *http.Request) {
	orgID := pathID(r, "id")
	org, err := s.Store.GetOrganization(r.Context(), orgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	sub, err := s.Store.GetSubscriptionWithPlan(r.Context(), orgID)
	if err != nil {
		sub = nil
	}
	outlets, err := s.Store.ListOutlets(r.Context(), orgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	staff, err := s.Store.ListStaff(r.Context(), orgID, "")
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	invoices, err := s.Store.ListSaaSInvoices(r.Context(), orgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	events, err := s.Store.ListOrgEvents(r.Context(), orgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, models.OrgDetail{
		Org: *org, Subscription: sub, Outlets: outlets,
		Staff: staff, Invoices: invoices, Events: events,
	})
}

func (s *Server) adminActor(r *http.Request) string {
	if c, ok := claimsFrom(r); ok {
		return c.ActorID
	}
	return ""
}

func (s *Server) handleAdminActivate(w http.ResponseWriter, r *http.Request) {
	orgID := pathID(r, "id")
	var req models.ActivateReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	switch req.Method {
	case "bank", "upi", "razorpay", "":
		if req.Method == "" {
			req.Method = "bank"
		}
	default:
		httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_method", "method must be bank, upi or razorpay"))
		return
	}
	sub, inv, err := s.Store.ActivateOrg(r.Context(), orgID, s.adminActor(r), req.Method,
		req.PeriodDays, req.AmountPaise, req.Reference, req.Notes)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"subscription": sub, "invoice": inv})
}

func (s *Server) handleAdminExtend(w http.ResponseWriter, r *http.Request) {
	orgID := pathID(r, "id")
	var req models.ExtendReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if err := s.Store.ExtendOrg(r.Context(), orgID, s.adminActor(r), req.Days, req.Notes); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"extended": true})
}

func (s *Server) handleAdminSuspend(w http.ResponseWriter, r *http.Request) {
	orgID := pathID(r, "id")
	var req models.ExtendReq // reuse for notes
	if err := httpx.Decode(r, &req); err != nil {
		req.Days = 0
	}
	if err := s.Store.SuspendOrg(r.Context(), orgID, s.adminActor(r), req.Notes); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"suspended": true})
}

func (s *Server) handleAdminCancel(w http.ResponseWriter, r *http.Request) {
	orgID := pathID(r, "id")
	var req models.ExtendReq
	if err := httpx.Decode(r, &req); err != nil {
		req.Days = 0
	}
	if err := s.Store.CancelOrgNow(r.Context(), orgID, s.adminActor(r), req.Notes); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"cancelled": true})
}

// handleAdminStats is a light platform overview (counts + 30-day revenue).
func (s *Server) handleAdminStats(w http.ResponseWriter, r *http.Request) {
	orgs, err := s.Store.ListOrganizations(r.Context(), "")
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	counts := map[string]int{}
	revenue := int64(0)
	invoiceCount := 0
	since := time.Now().AddDate(0, 0, -30)
	for _, org := range orgs {
		counts[org.Status]++
		invs, err := s.Store.ListSaaSInvoices(r.Context(), org.ID)
		if err == nil {
			for _, inv := range invs {
				invoiceCount++
				if inv.PaidAt.After(since) {
					revenue += inv.AmountPaise
				}
			}
		}
	}
	httpx.JSON(w, http.StatusOK, map[string]any{
		"org_counts":      counts,
		"total_orgs":      len(orgs),
		"invoices":        invoiceCount,
		"revenue_30d":     revenue,
		"revenue_30d_inr": toRupeeStr(revenue),
	})
}

func toRupeeStr(paise int64) string {
	rs := float64(paise) / 100.0
	return strconv.FormatFloat(rs, 'f', 2, 64)
}
