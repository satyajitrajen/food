// Package auth: bcrypt PIN hashing + JWT issuing/validation + roles.
package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"

	"foodpos/backend/internal/httpx"
)

const (
	AccessTTL  = 15 * time.Minute
	RefreshTTL = 7 * 24 * time.Hour
	// SSETicketTTL: how long a single-use /ws connect ticket stays valid.
	SSETicketTTL = 60 * time.Second
)

// Token scopes: staff (POS PIN login), owner (org account login) and admin
// (platform superadmin). Role is the POS role for staff, the account role for
// owners, and "superadmin" for platform admins.
const (
	ScopeStaff = "staff"
	ScopeOwner = "owner"
	ScopeAdmin = "admin"
	SuperRole  = "superadmin"
)

type Claims struct {
	Scope    string `json:"scope"`
	ActorID  string `json:"aid"`
	Name     string `json:"name"`
	Role     string `json:"role,omitempty"`
	OrgID    string `json:"org,omitempty"`
	OutletID string `json:"outlet,omitempty"`
	jwt.RegisteredClaims
}

type Manager struct {
	Secret []byte
	Cost   int
}

func New(secret string, cost int) *Manager {
	if cost < 4 {
		cost = 4
	}
	if cost > 15 {
		cost = 15
	}
	return &Manager{Secret: []byte(secret), Cost: cost}
}

func (m *Manager) HashPIN(pin string) (string, error) {
	b, err := bcrypt.GenerateFromPassword([]byte(pin), m.Cost)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

func (m *Manager) CheckPIN(hash, pin string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(pin)) == nil
}

// HashPassword hashes an owner/platform-admin password (same bcrypt scheme as
// staff PINs; the 4-15 cost clamp in New() keeps brute-force resistance sane).
func (m *Manager) HashPassword(pw string) (string, error) { return m.HashPIN(pw) }
func (m *Manager) CheckPassword(hash, pw string) bool     { return m.CheckPIN(hash, pw) }

func (m *Manager) issue(claims Claims) (string, error) {
	claims.RegisteredClaims = jwt.RegisteredClaims{
		ExpiresAt: jwt.NewNumericDate(time.Now().Add(AccessTTL)),
		IssuedAt:  jwt.NewNumericDate(time.Now()),
		Issuer:    "foodpos",
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(m.Secret)
}

// IssueStaffToken returns a signed staff JWT valid for 15 minutes.
func (m *Manager) IssueStaffToken(staffID, name, role, orgID, outletID string) (string, error) {
	return m.issue(Claims{
		Scope: ScopeStaff, ActorID: staffID, Name: name,
		Role: role, OrgID: orgID, OutletID: outletID,
	})
}

// IssueOwnerToken returns a signed org-owner JWT (role: owner/admin).
func (m *Manager) IssueOwnerToken(accountID, name, role, orgID string) (string, error) {
	return m.issue(Claims{
		Scope: ScopeOwner, ActorID: accountID, Name: name, Role: role, OrgID: orgID,
	})
}

// IssueAdminToken returns a signed platform-superadmin JWT.
func (m *Manager) IssueAdminToken(adminID, name string) (string, error) {
	return m.issue(Claims{
		Scope: ScopeAdmin, ActorID: adminID, Name: name, Role: SuperRole,
	})
}

// NewRefreshToken returns a fresh opaque refresh token plus its SHA-256
// hash (only the hash is ever stored server-side).
func NewRefreshToken() (token, hash string) {
	b := make([]byte, 32)
	_, _ = rand.Read(b)
	token = hex.EncodeToString(b)
	sum := sha256.Sum256([]byte(token))
	return token, hex.EncodeToString(sum[:])
}

// HashToken hashes a refresh token the same way NewRefreshToken does.
func HashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

// ---- Single-use SSE connect tickets ----
//
// EventSource clients cannot set an Authorization header, so the access JWT
// would have to ride in the URL query — and straight into proxy access logs.
// Instead the terminal exchanges its (authenticated) JWT for a single-use,
// 60-second ticket; the ticket in the query is worthless after one consume.

type sseTicket struct {
	claims   *Claims
	expires  time.Time
	tokenSum string // SHA-256 of the presented ticket (in-memory only)
}

type TicketStore struct {
	mu      sync.Mutex
	tickets map[string]sseTicket // keyed by token hash
	ttl     time.Duration
}

func NewTicketStore(ttl time.Duration) *TicketStore {
	if ttl <= 0 {
		ttl = 60 * time.Second
	}
	return &TicketStore{tickets: map[string]sseTicket{}, ttl: ttl}
}

// Issue returns a fresh one-time ticket that carries the caller's claims.
func (ts *TicketStore) Issue(claims *Claims) string {
	b := make([]byte, 32)
	_, _ = rand.Read(b)
	token := hex.EncodeToString(b)
	sum := HashToken(token)
	ts.purge()
	ts.tickets[sum] = sseTicket{claims: claims, tokenSum: sum, expires: time.Now().Add(ts.ttl)}
	return token
}

// Consume redeems a ticket exactly once; a used, unknown or expired ticket
// fails closed.
func (ts *TicketStore) Consume(token string) (*Claims, bool) {
	if token == "" {
		return nil, false
	}
	sum := HashToken(token)
	t, ok := ts.tickets[sum]
	if !ok || time.Now().After(t.expires) {
		return nil, false
	}
	delete(ts.tickets, sum) // single-use
	return t.claims, true
}

func (ts *TicketStore) purge() {
	now := time.Now()
	for k, t := range ts.tickets {
		if now.After(t.expires) {
			delete(ts.tickets, k)
		}
	}
}

func (m *Manager) Parse(tokenString string) (*Claims, error) {
	tok, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method %v", t.Header["alg"])
		}
		return m.Secret, nil
	})
	if err != nil {
		return nil, httpx.ErrUnauthorized
	}
	claims, ok := tok.Claims.(*Claims)
	if !ok || !tok.Valid {
		return nil, httpx.ErrUnauthorized
	}
	return claims, nil
}

// RoleRank maps POS roles to a numeric privilege level. Superadmin ranks
// highest but is never used on tenant routes (scope middleware gates that).
func RoleRank(role string) int {
	switch role {
	case "superadmin":
		return 5
	case "admin":
		return 4
	case "manager":
		return 3
	case "cashier":
		return 2
	case "waiter":
		return 1
	case "kitchen":
		// Display-only KOT role: rank 0 keeps it out of every RequireRole
		// gate; middleware.DenyRoles blocks its writes to money routes.
		return 0
	default:
		return 0
	}
}

// RequireRole ensures the claim's role meets the minimum rank.
func RequireRole(claims *Claims, minRole string) error {
	if RoleRank(claims.Role) < RoleRank(minRole) {
		return httpx.ErrForbidden
	}
	return nil
}

var ErrBadCredentials = errors.New("bad credentials")

func SanitizeRole(role string) string { return strings.ToLower(strings.TrimSpace(role)) }
