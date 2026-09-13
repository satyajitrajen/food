# Razorpay Subscriptions in the Flutter POS App — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let org admins see plan/subscription status in the POS app's Settings and open native Razorpay checkout to enable auto-renew or pay one cycle manually, with owner re-auth for billing actions and webhooks as the sole writer of subscription state.

**Architecture:** Two small backend endpoints (a staff-scoped status read registered OUTSIDE the entitlement-gate group; an owner-scoped manual-order endpoint reusing `billing.CreateCheckout`) plus a Flutter `SubscriptionCardBody` stateful widget in Settings that loads status via `PosProvider`, re-authenticates the owner one-shot, and opens checkout through a thin `RazorpayCheckout` wrapper around `razorpay_flutter`. Client payment events never mutate subscription state — only refresh.

**Tech Stack:** Go/chi backend (existing `internal/billing` Razorpay gateway), Flutter + provider, `razorpay_flutter ^1.4.6`.

**Spec:** `memory/design/DB-razorpay-subscriptions-app.md` (read it first).

**Environment notes:**
- Backend integration tests need Postgres on localhost:5432 — NOT available on this machine; they run in CI. Locally verify with `gofmt`, `go vet`, `go build` (this is the established workflow).
- Flutter tests run locally: `flutter test` and `flutter analyze`.
- Money: backend speaks integer PAISE (`price_paise`, gross = base + 18% via `storeRound`); Flutter models carry double RUPEES, converted only in `lib/core/api/dto.dart`.

---

### Task 1: Backend — staff subscription status endpoint

**Files:**
- Modify: `backend/internal/api/saas_renew_test.go` (tests, bottom of file)
- Modify: `backend/internal/models/saas.go` (new response struct)
- Modify: `backend/internal/api/handlers_saas_renew.go` (new handler)
- Modify: `backend/internal/api/server.go` (route, in the staff READS section)

- [ ] **Step 1: Write the failing tests**

Append to `backend/internal/api/saas_renew_test.go`:

```go
// The status read must sit outside the entitlement gate: an expired org is
// exactly when the app needs it. Staff token comes from registering an org
// (which creates an admin staff + outlet) and doing a staff PIN login.
func registerAndStaffLogin(t *testing.T, e *env, email string) (orgID string) {
	t.Helper()
	code, body := e.do(t, "POST", "/api/v1/auth/register", registerBody(email), false)
	if code != 201 {
		t.Fatalf("register failed: %d %v", code, body)
	}
	outlet, _ := body["outlet"].(map[string]any)
	outletID, _ := outlet["id"].(string)
	adminPin, _ := body["admin_pin"].(string)
	org, _ := body["org"].(map[string]any)
	orgID, _ = org["id"].(string)
	if outletID == "" || adminPin == "" || orgID == "" {
		t.Fatalf("register response incomplete: %v", body)
	}
	staffID := ""
	if err := e.st.DB.QueryRow(
		`SELECT id FROM staff WHERE org_id = ? AND role = 'admin'`, orgID).Scan(&staffID); err != nil {
		t.Fatal(err)
	}
	code, body = e.do(t, "POST", "/api/v1/auth/login", map[string]string{
		"staff_id": staffID, "pin": adminPin, "outlet_id": outletID,
	}, false)
	if code != 200 {
		t.Fatalf("staff login failed: %d %v", code, body)
	}
	token, _ := body["token"].(string)
	if token == "" {
		t.Fatalf("no staff token: %v", body)
	}
	e.token = token
	return orgID
}

func TestSubscriptionAppStatusForStaff(t *testing.T) {
	hits := map[string]string{}
	e, _ := newRenewEnv(t, &hits)
	orgID := registerAndStaffLogin(t, e, "status-staff@test")

	code, body := e.do(t, "GET", "/api/v1/saas/subscription/status", nil, true)
	if code != 200 {
		t.Fatalf("status failed: %d %v", code, body)
	}
	if body["plan_code"] != "pro" || body["status"] != "trial" {
		t.Fatalf("unexpected status payload: %v", body)
	}
	if body["gateway_status"] != "" {
		t.Fatalf("expected empty gateway_status, got %v", body["gateway_status"])
	}
	if body["price_paise"] != float64(199900) {
		t.Fatalf("unexpected price: %v", body["price_paise"])
	}

	// Below-manager roles are denied the billing read.
	hash, _ := e.mgr.HashPIN("7777")
	if _, err := e.st.DB.Exec(
		`INSERT INTO staff (id, org_id, outlet_id, name, role, pin_hash, is_active)
		 VALUES ('st-status-cashier', ?, NULL, 'Cash', 'cashier', ?, 1)`, orgID, hash); err != nil {
		t.Fatal(err)
	}
	code, body = e.do(t, "POST", "/api/v1/auth/login", map[string]string{
		"staff_id": "st-status-cashier", "pin": "7777",
		"outlet_id": e.outletIDForOrg(t, orgID),
	}, false)
	if code != 200 {
		t.Fatalf("cashier login failed: %d %v", code, body)
	}
	cashierToken := body["token"].(string)
	saved := e.token
	e.token = cashierToken
	code, _ = e.do(t, "GET", "/api/v1/saas/subscription/status", nil, true)
	if code != 403 {
		t.Fatalf("cashier must be denied, got %d", code)
	}
	e.token = saved
}
```

Add this small helper next to `subOrgIDForToken` in the same file:

```go
func (e *env) outletIDForOrg(t *testing.T, orgID string) string {
	t.Helper()
	id := ""
	if err := e.st.DB.QueryRow(
		`SELECT id FROM outlets WHERE org_id = ? LIMIT 1`, orgID).Scan(&id); err != nil {
		t.Fatal(err)
	}
	return id
}
```

(If the file already has a comparable helper, reuse it instead of duplicating.)

- [ ] **Step 2: Verify the tests fail to compile**

Run: `cd backend && go vet ./internal/api/`
Expected: FAIL — `handleSubscriptionAppStatus` route references a method that does not exist yet (or, before the route exists, the test fails on 404/401 at CI time; locally `go vet` catches the undefined symbol once the route is added in Step 4).

- [ ] **Step 3: Add the response model**

In `backend/internal/models/saas.go`, next to `RazorpaySubscriptionStart`:

```go
// SubscriptionAppStatus is the staff-scoped read behind the POS app's
// subscription card (GET /api/v1/saas/subscription/status).
type SubscriptionAppStatus struct {
	PlanCode      string     `json:"plan_code"`
	PlanName      string     `json:"plan_name"`
	Status        string     `json:"status"`
	GatewayStatus string     `json:"gateway_status"`
	PeriodEnd     *time.Time `json:"period_end,omitempty"`
	PricePaise    int64      `json:"price_paise"`
}
```

- [ ] **Step 4: Add the handler**

Append to `backend/internal/api/handlers_saas_renew.go`:

```go
// handleSubscriptionAppStatus backs the POS app's Settings subscription card.
// It is registered with the READS (outside the entitlement-gate group): the
// gate blocks by group membership, not HTTP method, and an expired org is
// exactly when the card is needed.
func (s *Server) handleSubscriptionAppStatus(w http.ResponseWriter, r *http.Request) {
	c, ok := claimsFrom(r)
	if !ok {
		httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
		return
	}
	sub, err := s.Store.GetSubscriptionWithPlan(r.Context(), c.OrgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	plan := sub.Plan
	if plan == nil {
		httpx.ErrorJSON(w, r, httpx.NewError(404, "no_plan", "Organization has no plan"))
		return
	}
	httpx.JSON(w, http.StatusOK, models.SubscriptionAppStatus{
		PlanCode:      plan.Code,
		PlanName:      plan.Name,
		Status:        sub.Status,
		GatewayStatus: sub.GatewayStatus,
		PeriodEnd:     sub.CurrentPeriodEnd,
		PricePaise:    plan.PricePaise,
	})
}
```

- [ ] **Step 5: Register the route (root-level static, staff chain)**

In `backend/internal/api/server.go`, at the ROOT level, immediately after the owner group (`r.Route("/api/v1/saas", ...)` block). The owner mount claims ALL `/api/v1/saas/*` subpaths with no fall-through, so an in-group registration in the staff group would be unreachable shadowed dead code; a root-level static route beats the mount's catch-all:

```go
	// Staff-scoped subscription status for the POS app's Settings card.
	// Root-level static route: /api/v1/saas/* is claimed by the owner mount
	// above, so this cannot be registered inside the staff group. The full
	// staff chain is replicated explicitly. A pure read — deliberately NOT
	// behind the entitlement gate so an expired org can still see its status
	// and renew (the gate blocks by group membership, not HTTP method).
	r.With(middleware.Auth(s.Auth), middleware.RequireScope(auth.ScopeStaff),
		middleware.StaffTenant(), middleware.RequireRole("manager")).
		Get("/api/v1/saas/subscription/status", s.handleSubscriptionAppStatus)
```

- [ ] **Step 6: Verify gates**

Run: `cd backend && gofmt -w internal/api internal/models && go vet ./... && go build ./...`
Expected: clean, no output.

- [ ] **Step 7: Commit**

```bash
git add backend/internal/api/saas_renew_test.go backend/internal/api/handlers_saas_renew.go backend/internal/api/server.go backend/internal/models/saas.go
git commit -m "feat(saas): staff-scoped subscription status read for the POS app"
```

---

### Task 2: Backend — owner manual renewal order endpoint

**Files:**
- Modify: `backend/internal/api/saas_renew_test.go` (fake `/v1/orders` + tests)
- Modify: `backend/internal/models/saas.go` (new response struct)
- Modify: `backend/internal/api/handlers_saas_renew.go` (new handler)
- Modify: `backend/internal/api/server.go` (route, owner group)

- [ ] **Step 1: Teach the fake gateway about orders**

In `newRenewEnv` (`backend/internal/api/saas_renew_test.go`), next to the other `record(...)` calls:

```go
	record("/v1/orders", `{"id":"order_fake1"}`)
```

- [ ] **Step 2: Write the failing test**

Append to `backend/internal/api/saas_renew_test.go`:

```go
func TestOwnerManualRenewalOrder(t *testing.T) {
	hits := map[string]string{}
	e, cfg := newRenewEnv(t, &hits)
	registerOwner(t, e, "renew-manual@test")
	orgID := subOrgIDForToken(t, e)
	ctx := context.Background()

	// One cycle at gross (pro base 199900 + 18% = 235882).
	code, body := e.do(t, "POST", "/api/v1/saas/subscription/manual-order", map[string]any{}, true)
	if code != 200 {
		t.Fatalf("manual order failed: %d %v", code, body)
	}
	if body["order_id"] != "order_fake1" {
		t.Fatalf("unexpected order id: %v", body)
	}
	if body["amount_paise"] != float64(235882) {
		t.Fatalf("unexpected amount: %v", body["amount_paise"])
	}
	if body["key_id"] != cfg.RazorpayKey {
		t.Fatalf("unexpected key id: %v", body["key_id"])
	}
	if orderBody := hits["/v1/orders|POST"]; !strings.Contains(orderBody, orgID) {
		t.Fatalf("order missing org_id note: %s", orderBody)
	}

	// While auto-renew is live the gateway owns billing — manual orders are refused.
	if _, err := e.st.SetOrgGatewaySubscription(ctx, orgID, "sub_fake1", "active"); err != nil {
		t.Fatal(err)
	}
	code, _ = e.do(t, "POST", "/api/v1/saas/subscription/manual-order", map[string]any{}, true)
	if code != 409 {
		t.Fatalf("expected 409 while auto-renew active, got %d", code)
	}

	// Unconfigured keys → 503.
	e2 := newEnvWithCfg(t, config.Load())
	registerOwner(t, e2, "renew-manual2@test")
	code, _ = e2.do(t, "POST", "/api/v1/saas/subscription/manual-order", map[string]any{}, true)
	if code != 503 {
		t.Fatalf("expected 503 unconfigured, got %d", code)
	}
}
```

- [ ] **Step 3: Add the response model**

In `backend/internal/models/saas.go`, next to `RazorpaySubscriptionStart`:

```go
// RazorpayManualOrder is the owner one-cycle checkout payload
// (POST /api/v1/saas/subscription/manual-order).
type RazorpayManualOrder struct {
	OrderID     string `json:"order_id"`
	KeyID       string `json:"key_id"`
	AmountPaise int64  `json:"amount_paise"`
	Currency    string `json:"currency"`
	PlanName    string `json:"plan_name"`
}
```

- [ ] **Step 4: Add the handler**

Append to `backend/internal/api/handlers_saas_renew.go`:

```go
// handleOwnerManualOrder creates a one-cycle Razorpay order for the org's
// current plan at gross (base + 18%) so the POS app can pay without the
// console. notes.org_id is set by CreateCheckout; payment.captured activates.
func (s *Server) handleOwnerManualOrder(w http.ResponseWriter, r *http.Request) {
	c, ok := claimsFrom(r)
	if !ok {
		httpx.ErrorJSON(w, r, httpx.ErrUnauthorized)
		return
	}
	gw := s.razorpayGateway()
	if gw == nil {
		httpx.ErrorJSON(w, r, httpx.NewError(503, "gateway_unconfigured", "Razorpay keys are not configured"))
		return
	}
	sub, err := s.Store.GetSubscriptionWithPlan(r.Context(), c.OrgID)
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}
	plan := sub.Plan
	if plan == nil {
		httpx.ErrorJSON(w, r, httpx.NewError(404, "no_plan", "Organization has no plan"))
		return
	}
	switch sub.GatewayStatus {
	case "active", "authenticated", "pending", "halted":
		httpx.ErrorJSON(w, r, httpx.NewError(409, "auto_renew_owns_billing",
			"Auto-renew is active — cancel it before paying manually"))
		return
	}
	gross := plan.PricePaise + storeRound(plan.PricePaise)
	co, err := gw.CreateCheckout(r.Context(), c.OrgID, gross, "manual renewal")
	if err != nil {
		httpx.ErrorJSON(w, r, httpx.NewError(502, "gateway_error", err.Error()))
		return
	}
	_ = s.Store.AddOrgEvent(r.Context(), c.OrgID, c.ActorID, "razorpay.manual_order_created",
		store.MetaJSON(map[string]any{"order_id": co.GatewayID, "amount_paise": gross}))
	httpx.JSON(w, http.StatusOK, models.RazorpayManualOrder{
		OrderID:     co.GatewayID,
		KeyID:       s.Cfg.RazorpayKey,
		AmountPaise: gross,
		Currency:    co.Currency,
		PlanName:    plan.Name,
	})
}
```

- [ ] **Step 5: Register the route**

In `backend/internal/api/server.go`, in the owner group right after `r.Post("/subscription/razorpay", s.handleOwnerStartSubscription)`:

```go
		r.Post("/subscription/manual-order", s.handleOwnerManualOrder)
```

- [ ] **Step 6: Verify gates**

Run: `cd backend && gofmt -w internal/api internal/models && go vet ./... && go build ./...`
Expected: clean, no output. (Tests execute in CI against the compose Postgres.)

- [ ] **Step 7: Commit**

```bash
git add backend/internal/api/saas_renew_test.go backend/internal/api/handlers_saas_renew.go backend/internal/api/server.go backend/internal/models/saas.go
git commit -m "feat(saas): owner one-cycle manual renewal order endpoint"
```

---

### Task 3: Flutter — subscription models + API parsers (TDD)

**Files:**
- Create: `lib/models/subscription_model.dart`
- Modify: `lib/core/api/dto.dart` (parsers at the money edge)
- Test: `test/dto_test.dart`

- [ ] **Step 1: Write the failing tests**

Append to `test/dto_test.dart` (follow the file's existing `expect(...)` style):

```dart
import 'package:food_pos/models/subscription_model.dart';
// (merge into the file's existing import block)

void main() {
  // ... existing tests ...

  group('subscription parsing', () {
    test('subscriptionStatusFromApi maps all fields with paise at the edge', () {
      final status = subscriptionStatusFromApi({
        'plan_code': 'pro',
        'plan_name': 'Pro',
        'status': 'trial',
        'gateway_status': '',
        'period_end': '2026-09-20T00:00:00Z',
        'price_paise': 199900,
      });
      expect(status.planCode, 'pro');
      expect(status.planName, 'Pro');
      expect(status.status, 'trial');
      expect(status.gatewayStatus, '');
      expect(status.periodEnd, DateTime.utc(2026, 9, 20));
      expect(status.priceRupees, 1999.0);
      expect(status.autoRenewLive, isFalse);
    });

    test('autoRenewLive covers live mandate states', () {
      SubscriptionStatus withGateway(String gw) => subscriptionStatusFromApi({
            'plan_code': 'pro', 'plan_name': 'Pro', 'status': 'active',
            'gateway_status': gw, 'price_paise': 199900,
          });
      expect(withGateway('active').autoRenewLive, isTrue);
      expect(withGateway('authenticated').autoRenewLive, isTrue);
      expect(withGateway('pending').autoRenewLive, isTrue);
      expect(withGateway('halted').autoRenewLive, isTrue);
      expect(withGateway('cancelled').autoRenewLive, isFalse);
      expect(withGateway('completed').autoRenewLive, isFalse);
      expect(withGateway('created').autoRenewLive, isFalse);
    });

    test('razorpayStartFromApi parses the checkout payload', () {
      final start = razorpayStartFromApi({
        'subscription_id': 'sub_1', 'key_id': 'rzp_test_1', 'plan_code': 'pro',
        'plan_name': 'Pro', 'amount_paise': 235882, 'currency': 'INR',
        'registration_paise': 10100,
      });
      expect(start.subscriptionId, 'sub_1');
      expect(start.keyId, 'rzp_test_1');
      expect(start.planName, 'Pro');
      expect(start.amountPaise, 235882);
      expect(start.currency, 'INR');
      expect(start.registrationPaise, 10100);
    });

    test('razorpayManualOrderFromApi parses the order payload', () {
      final order = razorpayManualOrderFromApi({
        'order_id': 'order_1', 'key_id': 'rzp_test_1', 'amount_paise': 235882,
        'currency': 'INR', 'plan_name': 'Pro',
      });
      expect(order.orderId, 'order_1');
      expect(order.amountPaise, 235882);
      expect(order.currency, 'INR');
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd "D:\Satyajit Nikam\FoodPOS" && flutter test test/dto_test.dart`
Expected: FAIL — `subscriptionStatusFromApi` / models not defined.

- [ ] **Step 3: Create the model**

Create `lib/models/subscription_model.dart`:

```dart
/// Subscription payloads for the POS app's Settings subscription card.
/// Money stays in paise ints here; `dto.dart` converts to rupees at the edge.

class SubscriptionStatus {
  final String planCode;
  final String planName;

  /// trial | active | past_due | suspended | expired | cancelled
  final String status;

  /// '' | created | authenticated | active | pending | halted | cancelled | completed
  final String gatewayStatus;
  final DateTime? periodEnd;
  final double priceRupees;

  SubscriptionStatus({
    required this.planCode,
    required this.planName,
    required this.status,
    required this.gatewayStatus,
    required this.periodEnd,
    required this.priceRupees,
  });

  /// A live (or being-authenticated) gateway mandate owns billing.
  bool get autoRenewLive =>
      gatewayStatus == 'active' ||
      gatewayStatus == 'authenticated' ||
      gatewayStatus == 'pending' ||
      gatewayStatus == 'halted';
}

class RazorpaySubscriptionStart {
  final String subscriptionId;
  final String keyId;
  final String planCode;
  final String planName;
  final int amountPaise;
  final String currency;
  final int registrationPaise;

  RazorpaySubscriptionStart({
    required this.subscriptionId,
    required this.keyId,
    required this.planCode,
    required this.planName,
    required this.amountPaise,
    required this.currency,
    required this.registrationPaise,
  });
}

class RazorpayManualOrder {
  final String orderId;
  final String keyId;
  final int amountPaise;
  final String currency;
  final String planName;

  RazorpayManualOrder({
    required this.orderId,
    required this.keyId,
    required this.amountPaise,
    required this.currency,
    required this.planName,
  });
}
```

- [ ] **Step 4: Add the parsers to dto.dart**

In `lib/core/api/dto.dart` — add to the import block:

```dart
import '../../models/subscription_model.dart';
```

and append at the end (uses the file's existing `_str`, `_int`, `toRupees` helpers):

```dart
SubscriptionStatus subscriptionStatusFromApi(Map<String, dynamic> j) =>
    SubscriptionStatus(
      planCode: _str(j['plan_code']),
      planName: _str(j['plan_name']),
      status: _str(j['status']),
      gatewayStatus: _str(j['gateway_status']),
      periodEnd: j['period_end'] == null
          ? null
          : DateTime.tryParse(j['period_end'].toString()),
      priceRupees: toRupees(_int(j['price_paise'])),
    );

RazorpaySubscriptionStart razorpayStartFromApi(Map<String, dynamic> j) =>
    RazorpaySubscriptionStart(
      subscriptionId: _str(j['subscription_id']),
      keyId: _str(j['key_id']),
      planCode: _str(j['plan_code']),
      planName: _str(j['plan_name']),
      amountPaise: _int(j['amount_paise']),
      currency: _str(j['currency']),
      registrationPaise: _int(j['registration_paise']),
    );

RazorpayManualOrder razorpayManualOrderFromApi(Map<String, dynamic> j) =>
    RazorpayManualOrder(
      orderId: _str(j['order_id']),
      keyId: _str(j['key_id']),
      amountPaise: _int(j['amount_paise']),
      currency: _str(j['currency']),
      planName: _str(j['plan_name']),
    );
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd "D:\Satyajit Nikam\FoodPOS" && flutter test test/dto_test.dart`
Expected: PASS (all, including existing).

- [ ] **Step 6: Commit**

```bash
git add lib/models/subscription_model.dart lib/core/api/dto.dart test/dto_test.dart
git commit -m "feat(app): subscription model + API parsers (paise at edge)"
```

---

### Task 4: Flutter — ApiClient token override + PosProvider billing methods

**Files:**
- Modify: `lib/core/api/api_client.dart:53-114`
- Modify: `lib/providers/pos_provider.dart` (SaaS section, after the license getters around line 468)

- [ ] **Step 1: Add a one-shot token override to ApiClient**

Billing calls carry an ephemeral OWNER token, not the staff session. In `lib/core/api/api_client.dart`, replace `request` and `_headers` and adjust `_send`:

```dart
  Map<String, String> _headers([String? tokenOverride]) {
    final h = <String, String>{'Content-Type': 'application/json'};
    final token = tokenOverride ?? session?.accessToken;
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
    Map<String, String>? query,
    bool auth = true,
    String? token,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    return _send(method, path, body, idempotencyKey, query, auth, timeout,
        token: token);
  }
```

In `_send`, add the `token` parameter and use it (header selection + skip the 401 refresh-retry for one-shot tokens):

```dart
  Future<dynamic> _send(
    String method,
    String path,
    Object? body,
    String? idempotencyKey,
    Map<String, String>? query,
    bool auth,
    Duration timeout, {
    bool retried = false,
    String? token,
  }) async {
    final uri = _uri(path, query);
    final headers = _headers(token);
    if (!auth) headers.remove('Authorization');
    if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;
```

and change the 401 retry condition to `token == null` (a one-shot owner token must never trigger a staff-session refresh):

```dart
    if (res.statusCode == 401 && auth && token == null && session != null && !retried) {
```

- [ ] **Step 2: Add provider state + methods**

In `lib/providers/pos_provider.dart` — `../core/api/dto.dart` is already imported (line 6). Add the model import:

```dart
import '../models/subscription_model.dart';
```

Then, in the `// ---- SaaS tenant + license ----` section, directly after the `licenseTokenVerified` getter (around line 468):

```dart
  // ---- Subscription card (Settings, admins) ----

  SubscriptionStatus? _subscriptionStatus;
  String? _subscriptionStatusError;
  String? _subscriptionActionError;

  SubscriptionStatus? get subscriptionStatus => _subscriptionStatus;
  String? get subscriptionStatusError => _subscriptionStatusError;
  String? get subscriptionActionError => _subscriptionActionError;

  /// Staff-scoped read for the Settings subscription card. Registered outside
  /// the entitlement gate server-side, so an expired org can still load it.
  Future<void> loadSubscriptionStatus() async {
    if (!apiEnabled || _api == null) return;
    try {
      final data =
          await _api!.request('GET', '/api/v1/saas/subscription/status');
      _subscriptionStatus =
          data is Map<String, dynamic> ? subscriptionStatusFromApi(data) : null;
      _subscriptionStatusError =
          _subscriptionStatus == null ? 'No subscription on file' : null;
    } on ApiException catch (e) {
      _subscriptionStatusError = e.message;
    } on NetworkException {
      _subscriptionStatusError = 'Server unreachable';
    }
    notifyListeners();
  }

  /// One-shot owner login for billing actions. Returns the owner token or
  /// null; the token is used for a single request and never persisted.
  Future<String?> loginOwnerForAction(String email, String password) async {
    if (_api == null) return null;
    try {
      final data = await _api!.request('POST', '/api/v1/auth/account/login',
          body: {'email': email, 'password': password}, auth: false);
      final token =
          data is Map<String, dynamic> ? data['token'] as String? : null;
      return (token != null && token.isNotEmpty) ? token : null;
    } on ApiException {
      return null;
    } on NetworkException {
      return null;
    }
  }

  Future<RazorpaySubscriptionStart?> startAutoRenew(String ownerToken) async {
    return _ownerBillingCall(ownerToken, '/api/v1/saas/subscription/razorpay',
        (j) => razorpayStartFromApi(j));
  }

  Future<RazorpayManualOrder?> createManualRenewal(String ownerToken) async {
    return _ownerBillingCall(
        ownerToken, '/api/v1/saas/subscription/manual-order',
        (j) => razorpayManualOrderFromApi(j));
  }

  Future<bool> cancelAutoRenew(String ownerToken) async {
    _subscriptionActionError = null;
    try {
      await _api!.request('POST', '/api/v1/saas/subscription/cancel',
          token: ownerToken);
      return true;
    } on ApiException catch (e) {
      _subscriptionActionError = e.message;
      notifyListeners();
      return false;
    } on NetworkException {
      _subscriptionActionError = 'Server unreachable';
      notifyListeners();
      return false;
    }
  }

  Future<T?> _ownerBillingCall<T>(
    String ownerToken,
    String path,
    T Function(Map<String, dynamic>) parse,
  ) async {
    _subscriptionActionError = null;
    try {
      final data = await _api!.request('POST', path, token: ownerToken);
      if (data is! Map<String, dynamic>) {
        _subscriptionActionError = 'Unexpected response';
        notifyListeners();
        return null;
      }
      notifyListeners();
      return parse(data);
    } on ApiException catch (e) {
      _subscriptionActionError = e.message;
      notifyListeners();
      return null;
    } on NetworkException {
      _subscriptionActionError = 'Server unreachable';
      notifyListeners();
      return null;
    }
  }
```

- [ ] **Step 3: Verify gates**

Run: `cd "D:\Satyajit Nikam\FoodPOS" && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/core/api/api_client.dart lib/providers/pos_provider.dart
git commit -m "feat(app): owner-token API override + provider billing methods"
```

---

### Task 5: Flutter — razorpay_flutter dep + checkout wrapper

**Files:**
- Modify: `pubspec.yaml` (dependencies)
- Create: `lib/core/payments/razorpay_checkout.dart`

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, in `dependencies:` after `url_launcher: ^6.3.1`:

```yaml
  razorpay_flutter: ^1.4.6
```

Then run: `cd "D:\Satyajit Nikam\FoodPOS" && flutter pub get`
Expected: `Got dependencies!` (or success output).

Platform notes (no action needed now): Android `minSdk = flutter.minSdkVersion` (21 ≥ 19 required); no shrinking configured. If `isMinifyEnabled` is ever turned on in `android/app/build.gradle.kts`, add the Razorpay proguard rules from the plugin README.

- [ ] **Step 2: Create the wrapper**

Create `lib/core/payments/razorpay_checkout.dart`:

```dart
import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';

class CheckoutResult {
  final bool success;
  final String? error;
  final String? wallet;

  const CheckoutResult({required this.success, this.error, this.wallet});
}

/// Thin wrapper over razorpay_flutter: opens native checkout and converts the
/// event stream into a single Future. Server webhooks own subscription state —
/// this result is UI feedback only, never a source of truth.
class RazorpayCheckout {
  final Razorpay _rzp = Razorpay();

  Future<CheckoutResult> open(Map<String, dynamic> options) {
    final completer = Completer<CheckoutResult>();

    void done(CheckoutResult result) {
      _rzp.clear();
      if (!completer.isCompleted) completer.complete(result);
    }

    void onSuccess(PaymentSuccessResponse _) =>
        done(const CheckoutResult(success: true));
    void onFailure(PaymentFailureResponse e) =>
        done(CheckoutResult(success: false, error: e.message ?? 'Payment failed'));
    void onWallet(ExternalWalletResponse w) =>
        done(CheckoutResult(success: false, wallet: w.walletName));

    _rzp.on(Razorpay.EVENT_PAYMENT_SUCCESS, onSuccess);
    _rzp.on(Razorpay.EVENT_PAYMENT_ERROR, onFailure);
    _rzp.on(Razorpay.EVENT_EXTERNAL_WALLET, onWallet);
    _rzp.open(options);
    return completer.future;
  }

  void dispose() => _rzp.clear();
}

Map<String, dynamic> subscriptionCheckoutOptions({
  required String keyId,
  required String subscriptionId,
  required String planName,
  String? email,
}) =>
    {
      'key': keyId,
      'subscription_id': subscriptionId,
      'name': 'FoodPOS',
      'description': planName,
      'theme': {'color': '#E2572B'},
      if (email != null && email.isNotEmpty) 'prefill': {'email': email},
    };

Map<String, dynamic> orderCheckoutOptions({
  required String keyId,
  required String orderId,
  required int amountPaise,
  required String currency,
  required String description,
}) =>
    {
      'key': keyId,
      'order_id': orderId,
      'amount': amountPaise,
      'currency': currency,
      'name': 'FoodPOS',
      'description': description,
      'theme': {'color': '#E2572B'},
    };
```

- [ ] **Step 3: Verify gates**

Run: `cd "D:\Satyajit Nikam\FoodPOS" && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/core/payments/razorpay_checkout.dart
git commit -m "feat(app): razorpay_flutter native checkout wrapper"
```

---

### Task 6: Flutter — SubscriptionCardBody widget + Settings wiring

**Files:**
- Create: `lib/screens/settings/subscription_card.dart`
- Modify: `lib/screens/settings/settings_screen.dart` (insert section after Restaurant Profile card, around line 56)

- [ ] **Step 1: Create the card body**

Create `lib/screens/settings/subscription_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/payments/razorpay_checkout.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';

/// Subscription rows + actions inside the Settings "Subscription" section
/// chrome (admins only; the parent gates visibility). Billing actions
/// re-authenticate the org owner one-shot; server webhooks own subscription
/// state — client payment results only trigger a refresh.
class SubscriptionCardBody extends StatefulWidget {
  const SubscriptionCardBody({super.key});

  @override
  State<SubscriptionCardBody> createState() => _SubscriptionCardBodyState();
}

class _SubscriptionCardBodyState extends State<SubscriptionCardBody>
    with WidgetsBindingObserver {
  final _checkout = RazorpayCheckout();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PosProvider>().loadSubscriptionStatus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _checkout.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<PosProvider>().loadSubscriptionStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final status = provider.subscriptionStatus;
    final error = provider.subscriptionStatusError;

    if (status == null) {
      if (error != null) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(error,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        );
      }
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: SizedBox(
            height: 18, width: 18,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final periodText = status.periodEnd == null
        ? '—'
        : DateFormat('dd MMM yyyy').format(status.periodEnd!.toLocal());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row('Plan', status.planName),
        _row('Status', _statusLabel(status.status)),
        _row('Auto-renew', status.autoRenewLive ? 'On' : 'Off'),
        _row('Next cycle', periodText),
        _row('Price', '₹${status.priceRupees.toStringAsFixed(0)}'),
        const SizedBox(height: 8),
        _actions(provider, status),
      ],
    );
  }

  Widget _actions(PosProvider provider, SubscriptionStatus status) {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
            height: 18, width: 18,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (status.autoRenewLive) {
      return Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => _cancelAutoRenew(provider),
          child: const Text('Cancel auto-renew'),
        ),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => _payOneCycle(provider),
          child: const Text('Pay one cycle now'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () => _enableAutoRenew(provider),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primaryOrange),
          child: const Text('Enable auto-renew'),
        ),
      ],
    );
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'trial':
        return 'Trial';
      case 'active':
        return 'Active';
      case 'past_due':
        return 'Past due';
      case 'suspended':
        return 'Suspended';
      case 'expired':
        return 'Expired';
      case 'cancelled':
        return 'Cancelled';
      default:
        return s.isEmpty ? '—' : s;
    }
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(value,
                textAlign: TextAlign.end,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.textDark)),
          ),
        ],
      ),
    );
  }

  /// One-shot owner sign-in dialog. Returns (token, email) or null.
  Future<(String, String)?> _askOwnerToken() {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String? error;
    return showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Owner sign-in'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Billing actions need the organization owner account.',
                  style: TextStyle(fontSize: 12)),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Owner email'),
              ),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final provider = context.read<PosProvider>();
                final token = await provider.loginOwnerForAction(
                    emailCtrl.text.trim(), passCtrl.text);
                if (!dialogContext.mounted) return;
                if (token == null) {
                  setDialogState(
                      () => error = 'Invalid owner email or password');
                  return;
                }
                Navigator.pop(
                    dialogContext, (token, emailCtrl.text.trim()));
              },
              child: const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enableAutoRenew(PosProvider provider) async {
    final creds = await _askOwnerToken();
    if (creds == null || !mounted) return;
    final (token, email) = creds;
    setState(() => _busy = true);
    try {
      final start = await provider.startAutoRenew(token);
      if (!mounted) return;
      if (start == null) {
        _snack(context, provider.subscriptionActionError ?? 'Could not start auto-renew');
        return;
      }
      final result = await _checkout.open(subscriptionCheckoutOptions(
        keyId: start.keyId,
        subscriptionId: start.subscriptionId,
        planName: start.planName,
        email: email,
      ));
      if (!mounted) return;
      if (result.wallet != null) {
        _snack(context, 'Payment handed off to ${result.wallet}');
      } else if (!result.success) {
        _snack(context, result.error ?? 'Payment cancelled');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      await provider.loadSubscriptionStatus();
    }
  }

  Future<void> _payOneCycle(PosProvider provider) async {
    final creds = await _askOwnerToken();
    if (creds == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final order = await provider.createManualRenewal(creds.$1);
      if (!mounted) return;
      if (order == null) {
        _snack(context, provider.subscriptionActionError ?? 'Could not create the order');
        return;
      }
      final result = await _checkout.open(orderCheckoutOptions(
        keyId: order.keyId,
        orderId: order.orderId,
        amountPaise: order.amountPaise,
        currency: order.currency,
        description: 'One cycle — ${order.planName}',
      ));
      if (!mounted) return;
      if (result.wallet != null) {
        _snack(context, 'Payment handed off to ${result.wallet}');
      } else if (!result.success) {
        _snack(context, result.error ?? 'Payment cancelled');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      await provider.loadSubscriptionStatus();
    }
  }

  Future<void> _cancelAutoRenew(PosProvider provider) async {
    final creds = await _askOwnerToken();
    if (creds == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final ok = await provider.cancelAutoRenew(creds.$1);
      if (!mounted) return;
      _snack(context, ok
          ? 'Auto-renew will stop at the end of this cycle'
          : provider.subscriptionActionError ?? 'Could not cancel auto-renew');
    } finally {
      if (mounted) setState(() => _busy = false);
      await provider.loadSubscriptionStatus();
    }
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)));
  }
}
```

- [ ] **Step 2: Wire the section into Settings**

In `lib/screens/settings/settings_screen.dart`, add the import:

```dart
import 'subscription_card.dart';
```

In the `ListView` children, immediately AFTER the Restaurant Profile section's closing `const SizedBox(height: 16),` (before the "Taxes & Additional Charges" card), insert:

```dart
            // Subscription (API terminals, admins only)
            if (provider.apiEnabled && provider.isAdmin) ...[
              _buildSettingsSection(
                title: 'Subscription',
                subtitle: 'Plan, billing & auto-renew',
                icon: Icons.workspace_premium_outlined,
                children: const [SubscriptionCardBody()],
              ),
              const SizedBox(height: 16),
            ],
```

- [ ] **Step 3: Verify gates**

Run: `cd "D:\Satyajit Nikam\FoodPOS" && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/screens/settings/subscription_card.dart lib/screens/settings/settings_screen.dart
git commit -m "feat(app): Settings subscription card with native Razorpay checkout"
```

---

### Task 7: Widget tests + full gates + docs

**Files:**
- Create: `test/subscription_card_test.dart`
- Modify: `memory/PROJECT_STATE.md`

- [ ] **Step 1: Write the widget tests**

Create `test/subscription_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_pos/models/subscription_model.dart';
import 'package:food_pos/providers/pos_provider.dart';
import 'package:food_pos/screens/settings/subscription_card.dart';
import 'package:provider/provider.dart';

/// Demo-mode provider (apiEnabled=false keeps network paths inert) with the
/// subscription getters overridden to inject card states.
class _FakePosProvider extends PosProvider {
  SubscriptionStatus? status;
  String? statusError;

  @override
  SubscriptionStatus? get subscriptionStatus => status;

  @override
  String? get subscriptionStatusError => statusError;

  @override
  Future<void> loadSubscriptionStatus() async {}
}

SubscriptionStatus _status(
    {String subStatus = 'trial', String gatewayStatus = ''}) {
  return SubscriptionStatus(
    planCode: 'pro',
    planName: 'Pro',
    status: subStatus,
    gatewayStatus: gatewayStatus,
    periodEnd: subStatus == 'trial' ? DateTime(2026, 9, 20) : null,
    priceRupees: 1999,
  );
}

Widget _wrap(PosProvider provider) =>
    ChangeNotifierProvider<PosProvider>.value(
      value: provider,
      child: const MaterialApp(
        home: Scaffold(
          body: ListView(children: [SubscriptionCardBody()]),
        ),
      ),
    );

void main() {
  testWidgets('shows plan, status and both payment actions when auto-renew is off',
      (tester) async {
    final provider = _FakePosProvider()..status = _status();
    await tester.pumpWidget(_wrap(provider));

    expect(find.text('Pro'), findsOneWidget);
    expect(find.text('Trial'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('Enable auto-renew'), findsOneWidget);
    expect(find.text('Pay one cycle now'), findsOneWidget);
    expect(find.text('Cancel auto-renew'), findsNothing);
  });

  testWidgets('shows cancel only when auto-renew is live', (tester) async {
    final provider = _FakePosProvider()
      ..status = _status(subStatus: 'active', gatewayStatus: 'active');
    await tester.pumpWidget(_wrap(provider));

    expect(find.text('On'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Enable auto-renew'), findsNothing);
    expect(find.text('Pay one cycle now'), findsNothing);
    expect(find.text('Cancel auto-renew'), findsOneWidget);
  });

  testWidgets('shows the load error when no status is available',
      (tester) async {
    final provider = _FakePosProvider()..statusError = 'No subscription on file';
    await tester.pumpWidget(_wrap(provider));

    expect(find.text('No subscription on file'), findsOneWidget);
    expect(find.text('Enable auto-renew'), findsNothing);
  });

  testWidgets('rebuilds when the provider notifies (webhook-driven refresh)',
      (tester) async {
    final provider = _FakePosProvider()..status = _status();
    await tester.pumpWidget(_wrap(provider));
    expect(find.text('Off'), findsOneWidget);

    provider.status = _status(subStatus: 'active', gatewayStatus: 'active');
    provider.notifyListeners();
    await tester.pump();

    expect(find.text('On'), findsOneWidget);
    expect(find.text('Cancel auto-renew'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the widget tests**

Run: `cd "D:\Satyajit Nikam\FoodPOS" && flutter test test/subscription_card_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 3: Run the full gates**

Run: `cd "D:\Satyajit Nikam\FoodPOS" && flutter analyze && flutter test`
Expected: `No issues found!` and all test suites pass (34 pre-existing + 4 new + dto additions).

Run backend gates: `cd backend && go vet ./... && go build ./...`
Expected: clean.

- [ ] **Step 4: Update PROJECT_STATE**

In `memory/PROJECT_STATE.md`, in the top `## Now` section's Razorpay bullet (after the cross-check sentence block), append:

```markdown
  App-side subscriptions (design DB-razorpay-subscriptions-app.md): staff-scoped
  GET /api/v1/saas/subscription/status (registered OUTSIDE the entitlement gate
  so expired orgs can renew) + owner POST /api/v1/saas/subscription/manual-order
  (one cycle at gross, 409 when auto-renew owns billing); Settings subscription
  card (admins) with one-shot owner re-auth and native razorpay_flutter
  checkout (subscription + order); webhooks remain the sole state writer.
```

- [ ] **Step 5: Commit**

```bash
git add test/subscription_card_test.dart memory/PROJECT_STATE.md
git commit -m "test(app): subscription card states + docs update"
```

---

## Self-Review (done at plan-writing time)

- **Spec coverage:** status endpoint (Task 1), manual-order (Task 2), models/parsers (Task 3), provider methods + owner re-auth support (Task 4), checkout wrapper + plugin (Task 5), card + settings wiring + refresh-on-open/resume/post-checkout (Task 6), error handling in card (503-hidden via null status + error text; 409 via action-error snackbars), widget tests + gates + docs (Task 7). LicenseBanner and table-screen block untouched per spec.
- **Type consistency:** `RazorpaySubscriptionStart`/`RazorpayManualOrder`/`SubscriptionStatus` field names match between model, dto parsers, backend JSON tags (`order_id`, `key_id`, `amount_paise`, `currency`, `plan_name`, `plan_code`, `plan_name`, `status`, `gateway_status`, `period_end`, `price_paise`), provider methods, and the card. `SetOrgGatewaySubscription(ctx, orgID, subID, status)` matches the store signature used by existing tests. `claimsFrom`, `storeRound`, `store.MetaJSON`, `httpx.*` all exist in the api package (used by handlers in the same files).
- **No placeholders:** every code step is complete code; every run step has expected output.
