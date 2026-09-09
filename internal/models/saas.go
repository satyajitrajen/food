package models

import "time"

// ---- SaaS: organizations, accounts, plans, subscriptions ----

// Organization lifecycle statuses (org.status and org_subscriptions.status).
const (
	OrgTrial     = "trial"
	OrgActive    = "active"
	OrgPastDue   = "past_due"
	OrgSuspended = "suspended"
	OrgExpired   = "expired"
	OrgClosed    = "closed"
)

const (
	SubTrial     = "trial"
	SubActive    = "active"
	SubPastDue   = "past_due"
	SubSuspended = "suspended"
	SubExpired   = "expired"
	SubCancelled = "cancelled"
)

type Organization struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Email     string    `json:"email"`
	GSTIN     string    `json:"gstin"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type Account struct {
	ID            string    `json:"id"`
	OrgID         string    `json:"org_id"`
	Name          string    `json:"name"`
	Email         string    `json:"email"`
	Role          string    `json:"role"` // owner | admin
	IsActive      bool      `json:"is_active"`
	EmailVerified bool      `json:"email_verified"`
	CreatedAt     time.Time `json:"created_at"`
}

type AccountCreate struct {
	OrgID        string `json:"org_id"`
	Name         string `json:"name"`
	Email        string `json:"email"`
	PasswordHash string `json:"-"`
	Role         string `json:"role"`
}

type PlatformAdmin struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Email     string    `json:"email"`
	CreatedAt time.Time `json:"created_at"`
}

type OrgCode struct {
	OrgID     string    `json:"org_id"`
	Code      string    `json:"code"`
	Active    bool      `json:"active"`
	CreatedAt time.Time `json:"created_at"`
}

type Plan struct {
	ID           string `json:"id"`
	Code         string `json:"code"`
	Name         string `json:"name"`
	PricePaise   int64  `json:"price_paise"`
	IntervalDays int    `json:"interval_days"`
	MaxOutlets   int    `json:"max_outlets"`
	MaxStaff     int    `json:"max_staff"`
	TrialDays    int    `json:"trial_days"`
	IsActive     bool   `json:"is_active"`
}

type OrgSubscription struct {
	OrgID              string     `json:"org_id"`
	PlanID             string     `json:"plan_id"`
	Status             string     `json:"status"`
	TrialEndsAt        *time.Time `json:"trial_ends_at"`
	CurrentPeriodStart *time.Time `json:"current_period_start"`
	CurrentPeriodEnd   *time.Time `json:"current_period_end"`
	CancelAtPeriodEnd  bool       `json:"cancel_at_period_end"`
	Notes              *string    `json:"notes"`
	UpdatedAt          time.Time  `json:"updated_at"`
	Plan               *Plan      `json:"plan,omitempty"`
}

type SaaSInvoice struct {
	ID          string     `json:"id"`
	OrgID       string     `json:"org_id"`
	InvoiceNo   string     `json:"invoice_no"`
	AmountPaise int64      `json:"amount_paise"` // taxable base (exclusive of GST)
	GSTPercent  float64    `json:"gst_percent"`
	TaxPaise    int64      `json:"tax_paise"`
	GrossPaise  int64      `json:"gross_paise"` // amount + tax = what customer pays
	Method      string     `json:"method"`      // bank | upi | razorpay
	PeriodStart *time.Time `json:"period_start"`
	PeriodEnd   *time.Time `json:"period_end"`
	PaidAt      time.Time  `json:"paid_at"`
	Reference   *string    `json:"reference"`
	Notes       *string    `json:"notes"`
	CreatedBy   *string    `json:"created_by"`
	CreatedAt   time.Time  `json:"created_at"`
}

type OrgEvent struct {
	ID     string    `json:"id"`
	OrgID  string    `json:"org_id"`
	Actor  *string   `json:"actor"`
	Action string    `json:"action"`
	Meta   string    `json:"meta"`
	Ts     time.Time `json:"ts"`
}

// Entitlement is returned at staff/owner login and used by POS terminals for
// offline grace enforcement. signed client-side (HMAC) in a later phase.
type Entitlement struct {
	Status     string    `json:"status"`
	ValidUntil time.Time `json:"valid_until"`
	GraceDays  int       `json:"grace_days"`
}

// ---- Requests / responses ----

type RegisterOrgReq struct {
	OrgName    string `json:"org_name"`
	OwnerName  string `json:"owner_name"`
	Email      string `json:"email"`
	Password   string `json:"password"`
	GSTIN      string `json:"gstin,omitempty"`
	OutletName string `json:"outlet_name"`
	Terminal   string `json:"terminal,omitempty"`
}

type RegisterOrgResp struct {
	Token        string          `json:"token"`
	RefreshToken string          `json:"refresh_token"`
	TokenType    string          `json:"token_type"`
	ExpiresAt    time.Time       `json:"expires_at"`
	Org          Organization    `json:"org"`
	Outlet       Outlet          `json:"outlet"`
	OrgCode      string          `json:"org_code"`
	AdminPIN     string          `json:"admin_pin"`
	Plan         Plan            `json:"plan"`
	Subscription OrgSubscription `json:"subscription"`
}

type AccountLoginReq struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type AccountLoginResp struct {
	Token            string       `json:"token"`
	RefreshToken     string       `json:"refresh_token"`
	TokenType        string       `json:"token_type"`
	ExpiresAt        time.Time    `json:"expires_at"`
	Account          Account      `json:"account"`
	Org              Organization `json:"org"`
	Entitlement      Entitlement  `json:"entitlement"`
	EntitlementToken string       `json:"entitlement_token,omitempty"`
}

type AdminLoginReq struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type AdminLoginResp struct {
	Token        string        `json:"token"`
	RefreshToken string        `json:"refresh_token"`
	TokenType    string        `json:"token_type"`
	ExpiresAt    time.Time     `json:"expires_at"`
	Admin        PlatformAdmin `json:"admin"`
}

type DeviceOptionsReq struct {
	OrgCode string `json:"org_code"`
}

type OutletCreate struct {
	Name     string `json:"name"`
	Address  string `json:"address"`
	Terminal string `json:"terminal"`
	GSTIN    string `json:"gstin,omitempty"`
	FSSAI    string `json:"fssai,omitempty"`
	Phone    string `json:"phone,omitempty"`
}

type OrgDetail struct {
	Org          Organization     `json:"org"`
	Subscription *OrgSubscription `json:"subscription"`
	Outlets      []Outlet         `json:"outlets"`
	Staff        []Staff          `json:"staff"`
	Invoices     []SaaSInvoice    `json:"invoices"`
	Events       []OrgEvent       `json:"events"`
}

// Superadmin subscription operations (manual billing).
type ActivateReq struct {
	Method      string `json:"method"`                 // bank | upi | razorpay
	PeriodDays  int    `json:"period_days,omitempty"`  // default plan interval
	AmountPaise int64  `json:"amount_paise,omitempty"` // default plan price
	Reference   string `json:"reference,omitempty"`
	Notes       string `json:"notes,omitempty"`
}

type ExtendReq struct {
	Days  int    `json:"days"`
	Notes string `json:"notes,omitempty"`
}

// ---- Account token ops (email verify / password reset) ----

type ForgotPasswordReq struct {
	Email string `json:"email"`
}

type ResetPasswordReq struct {
	Token       string `json:"token"`
	NewPassword string `json:"new_password"`
}

type VerifyEmailReq struct {
	Token string `json:"token"`
}

type MailResp struct {
	// Delivered is false when SMTP is unconfigured (dev fallback: token echoed).
	Delivered bool   `json:"delivered"`
	Token     string `json:"token,omitempty"` // echoed in dev when SMTP disabled
	Message   string `json:"message"`
}
