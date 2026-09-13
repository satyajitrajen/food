# DB / Feature brief: Razorpay subscriptions in the Flutter POS app

Date: 2026-09-13 · Branch: feature/saas-conversion · Companion to
DB-razorpay-subscriptions.md (backend + console auto-renew).

## Goal

Owners manage billing from the POS app itself: a Subscription card in Settings
shows plan/status/auto-renew state and offers native Razorpay checkout to
enable auto-renew or pay one cycle manually. The webhook remains the sole
writer of subscription state — client payment events only refresh UI.

Decisions (user-approved):
- Scope: status + enable auto-renew + manual one-cycle payment.
- Checkout: **native in-app** via `razorpay_flutter` (plugin passes the
  options bundle straight into the native CheckoutActivity; its delegate
  handles `razorpay_subscription_id`, so subscription checkout works even
  though docs pages don't call it out).
- Billing actions require **owner re-auth in-app** (email + password →
  `/api/v1/auth/account/login` → ephemeral owner token for that one action,
  never persisted). The app signs in as staff; admin is the in-app stand-in
  for "owner" (server enforces scopes regardless).

## Backend additions

- `GET /api/v1/saas/subscription/status` — staff token (admin/manager);
  returns `{plan_code, plan_name, status, gateway_status, period_end,
  price_paise, registration_paise}`. GETs pass the entitlement gate, so an
  expired org can still open the card and renew. A pure read — no gateway
  calls, no key-config branching (the app hides payment actions based on
  gateway errors at action time, not here).
- `POST /api/v1/saas/subscription/manual-order` — owner token. Creates a
  Razorpay ORDER for one cycle at gross (base + 18% via storeRound), notes
  `{org_id}` (existing manual-capture path activates on payment.captured).
  Returns `{order_id, key_id, amount_paise, currency, plan_name}`.
  Guards: 503 gateway_unconfigured; 409 when gateway_status is
  active/authenticated/pending/halted (auto-renew owns billing).
- Start (`POST /saas/subscription/razorpay`) and cancel
  (`POST /saas/subscription/cancel`) already exist — unchanged.

KEY_SECRET never leaves the server: both checkouts receive KEY_ID only.

## App: data layer

- PosProvider: `loadSubscriptionStatus()` (staff token), `startAutoRenew`,
  `createManualRenewal`, `cancelAutoRenew` (owner token param) — ad-hoc
  `_api.request` calls per existing convention.
- `SubscriptionStatus` model parsed in `core/api/dto.dart`; paise at edge,
  `toRupees` at display.
- Owner re-auth helper: dialog pattern mirrors verifyManagerPin; returns the
  owner token or null; inline error on login failure.

## App: checkout wrapper

`lib/core/payments/razorpay_checkout.dart` wraps `razorpay_flutter ^1.4.6`:
- `openSubscriptionCheckout(key, subscriptionId, {planName, email})` →
  options `{key, subscription_id, name: 'FoodPOS', description: planName,
  theme.color: '#e2572b', prefill.email}`.
- `openOrderCheckout(key, orderId, amountPaise, currency, {planName})` →
  options `{key, order_id, amount, currency, name, description,
  theme.color}`.
- Maps plugin events payment_success / payment_error / external_wallet to
  callbacks. Success NEVER mutates subscription state — triggers refresh.

Android: minSdk = flutter.minSdkVersion (21 ≥ 19) OK. No shrinking
configured today; if `isMinifyEnabled` is ever turned on, add the Razorpay
proguard rules from the plugin README (release-config caveat). iOS 10+.

## App: Settings Subscription card (admins only)

Rows: Plan · Status (+days left, reuse entitlement snapshot) · Auto-renew
(gateway state) · Next cycle date. Actions:
- **Enable auto-renew** and **Pay one cycle now** share one visibility rule:
  shown only when gateway_status ∉ {active, authenticated, pending, halted}
  — enable → owner re-auth → start endpoint → native subscription checkout;
  pay-now → owner re-auth → manual-order → native order checkout.
- **Cancel auto-renew** when gateway_status = active → owner re-auth →
  cancel endpoint.

Visible to `isAdmin` (billing is owner-level; managers don't need it).
Refresh on card open, after checkout closes, and on app resume
(didChangeAppLifecycleState). LicenseBanner and the table-screen renewal
block stay unchanged.

## Error handling

- Owner login failure → inline error in dialog.
- 409 already-active → refresh card + notice.
- 503 gateway_unconfigured → notice + actions hidden.
- Checkout error/dismiss → snackbar only; no state mutation.

## Tests

- Backend integration: status endpoint (staff token; readable while expired);
  manual-order (owner token; gross = base + 18%; notes.org_id present;
  409 when auto-renew live; 503 unconfigured) against the fake gateway.
- App: SubscriptionStatus parse tests (dto) + widget tests for card states;
  gates `flutter analyze` + `flutter test`.
