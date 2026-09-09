package api

// SaaS auth + owner APIs: self-registration, owner (email/password) login,
// terminal bootstrap by org code, and owner-scoped org management.

import (
	"crypto/rand"
	"fmt"
	"math/big"
	"net/http"
	"strings"
	"time"

	"foodpos/backend/internal/auth"
	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/mail"
	"foodpos/backend/internal/middleware"
	"foodpos/backend/internal/models"
	"foodpos/backend/internal/store"
)

const ownerSessionTTL = auth.RefreshTTL

// ---- Registration ----

func (s *Server) handleRegisterOrg(w http.ResponseWriter, r *http.Request) {
	var req models.RegisterOrgReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	req.OrgName = strings.TrimSpace(req.OrgName)
	req.Email = strings.ToLower(strings.TrimSpace(req.Email))
	req.OwnerName = strings.TrimSpace(req.OwnerName)
	req.OutletName = strings.TrimSpace(req.OutletName)
	if req.OrgName == "" || req.OwnerName == "" || req.Email == "" || req.OutletName == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_fields", "org_name, owner_name, email and outlet_name are required"))
		return
	}
	if len(req.Password) < 8 {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "weak_password", "Password must be at least 8 characters"))
		return
	}

	pwHash, err := s.Auth.HashPassword(req.Password)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	// Initial POS admin PIN (4 digits) shown once to the owner.
	pin, err := randomPIN()
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	pinHash, err := s.Auth.HashPIN(pin)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}

	res, err := s.Store.RegisterOrg(r.Context(), req.OrgName, req.Email, req.GSTIN,
		req.OwnerName, pwHash, req.OutletName, req.Terminal, pinHash)
	if err != nil {
		if isUniqueViolation(err) {
			httpx.ErrorJSON(w, r, httpx.NewError(409, "email_taken", "An account with this email already exists"))
			return
		}
		httpx.ErrorJSON(w, r, err)
		return
	}

	token, err := s.Auth.IssueOwnerToken(res.Account.ID, res.Account.Name, res.Account.Role, res.Org.ID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	refresh, hash := auth.NewRefreshToken()
	if err := s.Store.CreateSession(r.Context(), auth.ScopeOwner, res.Account.ID, hash,
		time.Now().Add(ownerSessionTTL)); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}

	// Welcome e-mail (with verification link) when SMTP is configured.
	sender := s.mailer()
	if sender.Enabled() {
		if vt, verr := s.Store.CreateAccountToken(r.Context(), res.Account.ID, store.TokenVerify, accountTokenTTL); verr == nil {
			go func() {
				_ = sender.Send(req.Email, "Welcome to FoodPOS",
					mail.Welcome(req.OwnerName, req.OrgName, s.Cfg.AppBaseURL, vt))
			}()
		}
	}

	httpx.JSON(w, http.StatusCreated, models.RegisterOrgResp{
		Token: token, RefreshToken: refresh, TokenType: "Bearer",
		ExpiresAt:    time.Now().Add(auth.AccessTTL),
		Org:          res.Org,
		Outlet:       res.Outlet,
		OrgCode:      res.OrgCode,
		AdminPIN:     pin,
		Plan:         *res.Plan,
		Subscription: *res.Subscription,
	})
}

// ---- Owner account login / refresh / logout ----

func (s *Server) handleAccountLogin(w http.ResponseWriter, r *http.Request) {
	var req models.AccountLoginReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	req.Email = strings.ToLower(strings.TrimSpace(req.Email))
	acc, err := s.Store.GetAccountByEmail(r.Context(), req.Email)
	if err != nil {
		httpx.ErrorJSON(w, r, httpx.NewError(401, "bad_credentials", "Invalid email or password"))
		return
	}
	if !acc.IsActive || !s.Auth.CheckPassword(acc.PasswordHash, req.Password) {
		httpx.ErrorJSON(w, r, httpx.NewError(401, "bad_credentials", "Invalid email or password"))
		return
	}
	org, err := s.Store.GetOrganization(r.Context(), acc.OrgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	token, err := s.Auth.IssueOwnerToken(acc.ID, acc.Name, acc.Role, acc.OrgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	refresh, hash := auth.NewRefreshToken()
	if err := s.Store.CreateSession(r.Context(), auth.ScopeOwner, acc.ID, hash, time.Now().Add(ownerSessionTTL)); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	ent, err := s.Store.GetEntitlement(r.Context(), org.ID)
	if err != nil {
		ent = &models.Entitlement{Status: org.Status, GraceDays: store.GraceDays, ValidUntil: time.Now().AddDate(0, 0, 7)}
	}
	httpx.JSON(w, http.StatusOK, models.AccountLoginResp{
		Token: token, RefreshToken: refresh, TokenType: "Bearer",
		ExpiresAt: time.Now().Add(auth.AccessTTL),
		Account:   acc.Account, Org: *org, Entitlement: *ent,
		EntitlementToken: s.signedEntitlementToken(ent),
	})
}

func (s *Server) handleAccountRefresh(w http.ResponseWriter, r *http.Request) {
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
	if sess.Revoked || time.Now().After(sess.ExpiresAt) || sess.Scope != auth.ScopeOwner {
		httpx.ErrorJSON(w, r, httpx.NewError(401, "invalid_refresh_token", "Refresh token is expired or revoked"))
		return
	}
	acc, err := s.Store.GetAccount(r.Context(), sess.ActorID)
	if err != nil || !acc.IsActive {
		httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
		return
	}
	org, err := s.Store.GetOrganization(r.Context(), acc.OrgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	_ = s.Store.RevokeSession(r.Context(), sess.ID)
	token, err := s.Auth.IssueOwnerToken(acc.ID, acc.Name, acc.Role, acc.OrgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	refresh, hash := auth.NewRefreshToken()
	if err := s.Store.CreateSession(r.Context(), auth.ScopeOwner, acc.ID, hash, time.Now().Add(ownerSessionTTL)); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	ent, err := s.Store.GetEntitlement(r.Context(), org.ID)
	if err != nil {
		ent = &models.Entitlement{Status: org.Status, GraceDays: store.GraceDays, ValidUntil: time.Now().AddDate(0, 0, 7)}
	}
	httpx.JSON(w, http.StatusOK, models.AccountLoginResp{
		Token: token, RefreshToken: refresh, TokenType: "Bearer",
		ExpiresAt: time.Now().Add(auth.AccessTTL),
		Account:   acc.Account, Org: *org, Entitlement: *ent,
		EntitlementToken: s.signedEntitlementToken(ent),
	})
}

func (s *Server) handleAccountLogout(w http.ResponseWriter, r *http.Request) {
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

// ---- Terminal bootstrap by org code ----

func (s *Server) handleDeviceOptions(w http.ResponseWriter, r *http.Request) {
	var req models.DeviceOptionsReq
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	org, err := s.Store.GetOrgByCode(r.Context(), strings.ToUpper(strings.TrimSpace(req.OrgCode)))
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	outlets, err := s.Store.ListOutlets(r.Context(), org.ID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	staff, err := s.Store.ListStaff(r.Context(), org.ID, "")
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{
		"org_id": org.ID, "org_name": org.Name,
		"outlets": outlets, "staff": staff,
	})
}

// ---- Owner-scoped org management (/api/v1/saas) ----

func (s *Server) handleSaaSMe(w http.ResponseWriter, r *http.Request) {
	c, ok := middleware.ClaimsFrom(r.Context())
	if !ok || c.Scope != auth.ScopeOwner {
		httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
		return
	}
	acc, err := s.Store.GetAccount(r.Context(), c.ActorID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	org, err := s.Store.GetOrganization(r.Context(), c.OrgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	sub, err := s.Store.GetSubscriptionWithPlan(r.Context(), c.OrgID)
	if err != nil {
		sub = nil
	}
	httpx.JSON(w, http.StatusOK, map[string]any{
		"account": acc, "org": org, "subscription": sub,
	})
}

func (s *Server) handleSaaSOrg(w http.ResponseWriter, r *http.Request) {
	c, _ := middleware.ClaimsFrom(r.Context())
	outlets, err := s.Store.ListOutlets(r.Context(), c.OrgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	staff, err := s.Store.ListStaff(r.Context(), c.OrgID, "")
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	invoices, err := s.Store.ListSaaSInvoices(r.Context(), c.OrgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	events, err := s.Store.ListOrgEvents(r.Context(), c.OrgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	org, err := s.Store.GetOrganization(r.Context(), c.OrgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	sub, err := s.Store.GetSubscriptionWithPlan(r.Context(), c.OrgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusOK, models.OrgDetail{
		Org: *org, Subscription: sub, Outlets: outlets,
		Staff: staff, Invoices: invoices, Events: events,
	})
}

func (s *Server) handleSaaSCreateOutlet(w http.ResponseWriter, r *http.Request) {
	c, _ := middleware.ClaimsFrom(r.Context())
	var req models.OutletCreate
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if strings.TrimSpace(req.Name) == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "missing_fields", "outlet name is required"))
		return
	}
	ok, err := s.Store.EntitlementOK(r.Context(), c.OrgID)
	if err != nil || !ok {
		httpx.ErrorJSON(w, r, httpx.NewError(402, "subscription_required", "An active subscription is required"))
		return
	}
	sub, err := s.Store.GetSubscriptionWithPlan(r.Context(), c.OrgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	count, err := s.Store.CountOutlets(r.Context(), c.OrgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if sub.Plan != nil && count >= sub.Plan.MaxOutlets {
		httpx.ErrorJSON(w, r, httpx.NewError(409, "plan_limit",
			fmt.Sprintf("Plan allows at most %d outlet(s)", sub.Plan.MaxOutlets)))
		return
	}
	out, err := s.Store.CreateOutlet(r.Context(), c.OrgID, models.Outlet{
		Name: req.Name, Address: req.Address, Terminal: req.Terminal,
		GSTIN: req.GSTIN, FSSAI: req.FSSAI, Phone: req.Phone,
	})
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	_ = s.Store.AddOrgEvent(r.Context(), c.OrgID, c.ActorID, "outlet.created", store.MetaJSON(map[string]any{"outlet_id": out.ID}))
	httpx.JSON(w, http.StatusCreated, out)
}

func (s *Server) handleSaaSCreateStaff(w http.ResponseWriter, r *http.Request) {
	c, _ := middleware.ClaimsFrom(r.Context())
	var req models.StaffCreate
	if err := httpx.Decode(r, &req); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	if len(req.PIN) < 4 || len(req.PIN) > 6 || !allDigits(req.PIN) {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_pin", "PIN must be 4-6 digits"))
		return
	}
	switch req.Role {
	case "admin", "manager", "cashier", "waiter", "kitchen":
	default:
		httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_role", "Unknown staff role"))
		return
	}
	if req.OutletID != nil {
		o, err := s.Store.GetOutlet(r.Context(), *req.OutletID)
		if err != nil || o.OrgID != c.OrgID {
			httpx.ErrorJSON(w, r, httpx.NewError(400, "invalid_outlet", "Outlet does not belong to this organization"))
			return
		}
	}
	if err := s.enforceStaffLimit(r, c.OrgID); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	hash, err := s.Auth.HashPIN(req.PIN)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	st, err := s.Store.CreateStaff(r.Context(), c.OrgID, req, hash)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, st)
}

// handleSaaSCancelSubscription sets cancel-at-period-end for the org.
func (s *Server) handleSaaSCancelSubscription(w http.ResponseWriter, r *http.Request) {
	c, _ := middleware.ClaimsFrom(r.Context())
	sub, err := s.Store.GetSubscription(r.Context(), c.OrgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	next := *sub
	next.CancelAtPeriodEnd = true
	if err := s.Store.UpsertSubscription(r.Context(), &next); err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	_ = s.Store.AddOrgEvent(r.Context(), c.OrgID, c.ActorID, "sub.cancel_requested", "{}")
	httpx.JSON(w, http.StatusOK, map[string]any{"cancel_at_period_end": true})
}

// ---- helpers ----

func randomPIN() (string, error) {
	const digits = "0123456789"
	b := make([]byte, 4)
	for i := range b {
		n, err := rand.Int(rand.Reader, big.NewInt(10))
		if err != nil {
			return "", err
		}
		b[i] = digits[n.Int64()]
	}
	return string(b), nil
}

func isUniqueViolation(err error) bool {
	msg := err.Error()
	return strings.Contains(msg, "unique") || strings.Contains(msg, "duplicate") ||
		strings.Contains(msg, "23505")
}
