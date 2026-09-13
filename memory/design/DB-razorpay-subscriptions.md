# DB / Feature brief: Razorpay Subscriptions (auto-renew)

Date: 2026-09-13 · Branch: feature/saas-conversion · Closes review finding M2 (renewals).

## Goal

Auto-renewing subscriptions via Razorpay Subscriptions API. Owner clicks
"Enable auto-renew" in the console → hosted Razorpay checkout on a
`subscription_id` → webhooks keep the local subscription lifecycle in sync.
One-time ₹101 registration fee charged with the first cycle as a Razorpay
add-on (`RAZORPAY_REGISTRATION_AMOUNT_PAISE=10100`).

## Money & GST rules (must match existing billing)

- `plans.price_paise` is the taxable BASE (GST 18% on top, SaaSGSTPercent).
- Razorpay plan amounts are created at GROSS (base + 18%) — same convention as
  the existing admin Orders checkout ("charge the gross so the webhook can
  extract the base back").
- `subscription.charged` → invoice base: **detected structurally** — gross >
  planGross (base + 18%) means the registration add-on is present, so invoice
  records `plan.PricePaise`; otherwise base = round(gross/1.18). (Status-based
  trial detection was rejected: a first charge can also arrive after the trial
  has already expired.)

## Schema (migration 010)

- `plans.gateway_plan_id TEXT NOT NULL DEFAULT ''`
- `org_subscriptions.gateway_subscription_id TEXT NOT NULL DEFAULT ''`
- `org_subscriptions.gateway_status TEXT NOT NULL DEFAULT ''` (razorpay-side:
  created/authenticated/active/pending/halted/cancelled/completed)
- index on `org_subscriptions(gateway_subscription_id)` (webhook fallback lookup)
- **unique partial index** `idx_saas_invoices_org_reference` on
  `saas_invoices(org_id, reference)` where reference is non-empty — DB-backed
  webhook idempotency; the duplicate guard alone has a delivery race

## Gateway additions (internal/billing)

`RazorpayGateway` gets an injectable base URL (tests point it at httptest;
config `FOODPOS_RAZORPAY_BASE_URL` defaults to the live API). New methods:
- `CreatePlan(name, amountPaise, currency, intervalDays)` → plan id
  (`period` monthly ≤31d else yearly, interval 1)
- `CreateSubscription(planID, orgID, totalCount)` → sub id + status,
  notes `{org_id}` (renewals carry org via webhook notes; fallback DB lookup)
- `CreateSubscriptionAddon(subID, name, amountPaise, currency)` — the ₹101
  registration fee; attached before first checkout so it lands in cycle 1
- `CancelSubscription(subID, atCycleEnd)` → new gateway status

## Lifecycle mapping (webhook → local state)

| Razorpay event | Local effect |
|---|---|
| subscription.charged | idempotent per payment id (reference lookup) → ActivateOrg (new paid period + invoice). Duplicate delivery no-ops. |
| subscription.authenticated | persist gateway ids, gateway_status=authenticated |
| subscription.activated | gateway_status=active |
| subscription.pending / halted | gateway_status + audit org_event |
| subscription.cancelled (immediate) | gateway_status=cancelled; if a paid period is still running → cancel_at_period_end (flag set, access kept until it ends); else sub=cancelled + org expired |
| subscription.completed (cycle-end cancel) | gateway_status=completed ONLY — never mutates local status; the billing cron lapses the sub when the running period ends |

**Unresolvable payloads return 200** with an `ignored`/`org_unresolved`/`no_payment_id`
reason, never 4xx — Razorpay retries non-2xx deliveries and can disable the
endpoint. Unknown events → 200 ignored.

payment.captured skips payments carrying a `subscription_id`
(`subscription.charged` owns subscription billing — Razorpay double-fires both
events for the same payment); manual captures are ignored while
gateway_status=active ("auto_renew_owns_billing") but still drive
manual Orders activation otherwise. payment.failed / refunded unchanged: audit
org_event only.

The ₹101 registration add-on is **intentionally not invoiced** — SaaS invoices
track the taxable plan base only; the fee is visible in Razorpay and the
org_event audit (registration_paise). The 409 "already started" guard on the
start endpoint covers active AND authenticated/pending/halted so a second live
mandate can't be created while the first is being authenticated.

## API

- Owner: `POST /api/v1/saas/subscription/razorpay` → ensures Razorpay plan for
  the org's current plan (gross amount), creates subscription (monthly → 12
  cycles, annual → 5), attaches registration add-on when
  `RazorpayRegistrationAmountPaise > 0`, persists ids, returns
  `{subscription_id, key_id, plan_code, amount_paise, currency, registration_paise}`.
- Owner cancel (`/subscription/cancel`) now also best-effort cancels the
  gateway subscription at cycle end.
- Console: OwnerPanel "Enable auto-renew" → loads checkout.js, opens hosted
  checkout with `subscription_id`; lifecycle updates arrive via webhooks.

## Config

`FOODPOS_RAZORPAY_CURRENCY` (default INR),
`FOODPOS_RAZORPAY_REGISTRATION_AMOUNT_PAISE` (default 10100),
`FOODPOS_RAZORPAY_BASE_URL` (default https://api.razorpay.com).
Live keys live ONLY in gitignored `.env` — never in tracked files.

## Tests

- billing: httptest fake Razorpay — plan/sub/addon/cancel request bodies.
- api integration: start endpoint (trial org → subscription_id + key_id, add-on
  amount, gateway ids persisted) and subscription.charged (expired org
  reactivates, invoice created, duplicate payment id → no second invoice).
  Webhook lifecycle: cancel-with-running-period keeps access +
  cancel_at_period_end; completed records only; cron lapse then cancelled →
  cancelled. Double-fire: payment.captured with subscription_id ignored;
  manual capture while auto-renew active ignored. Structural first-charge
  detection after trial expiry. Bad webhook signature → 401.
