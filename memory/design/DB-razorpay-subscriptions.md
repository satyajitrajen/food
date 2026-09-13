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
- `subscription.charged` → invoice base: first charge (sub was `trial`) uses
  `plan.PricePaise` (payment also contains the registration add-on, which is
  NOT part of the subscription invoice); renewals extract base = round(gross/1.18).

## Schema (migration 010)

- `plans.gateway_plan_id TEXT NOT NULL DEFAULT ''`
- `org_subscriptions.gateway_subscription_id TEXT NOT NULL DEFAULT ''`
- `org_subscriptions.gateway_status TEXT NOT NULL DEFAULT ''` (razorpay-side:
  created/authenticated/active/pending/halted/cancelled/completed)
- index on `org_subscriptions(gateway_subscription_id)` (webhook fallback lookup)

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
| subscription.cancelled (immediate) | gateway_status=cancelled; if local period still future → cancel_at_period_end, else sub=cancelled + org expired |
| subscription.completed (cycle-end cancel) | gateway_status=completed; sub=expired + org expired if still active/past_due |

payment.captured / payment.failed / payment.refunded behavior unchanged.

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
