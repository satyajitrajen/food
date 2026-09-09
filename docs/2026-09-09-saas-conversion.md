# SaaS conversion — backend runbook (2026-09-09)

FoodPOS is now multi-tenant: an **organization** owns outlets and staff, and a
subscription gates paid writes. Owners self-register; a **platform superadmin**
manages billing manually (bank/UPI receipt → activate) behind a gateway
interface (Razorpay adapter is a future milestone).

Full architecture + phased plan: `docs/../saas-architecture.md` (root workspace)
and `../docs/PRD.md` for product requirements.

## Tenant model

```
organization (trial|active|past_due|suspended|expired|closed)
├── accounts (email+password owners; scope: owner)
├── org_codes (short join code for POS terminal bootstrap)
├── org_subscriptions (1:1; plan_id → plans; one "pro" plan seeded)
├── saas_invoices (manual billing records; SAAS-INV-<n> per org)
├── org_events (lifecycle audit)
└── outlets (org_id) → staff (org_id, outlet_id NULL = org-wide) → POS data
platform_admins (email+password; scope: admin = superadmin)
```

JWT claims now carry a token `scope` (`staff|owner|admin`), `org_id` and
`outlet_id`. POS routes require scope `staff` and reject any `?outlet_id=`
that does not match the claim (tenant can no longer be overridden by a query
param). Refresh tokens are stored in the generic `auth_refresh` table with the
tenant binding, so a refresh re-issues the full claim set.

## New environment variables

| Var | Purpose |
|-----|---------|
| `FOODPOS_SUPERADMIN_EMAIL` / `FOODPOS_SUPERADMIN_PASSWORD` | Creates the platform superadmin on first boot (idempotent). |
| `FOODPOS_UPLOAD_DIR` | Menu photo storage (existing). |
| `FOODPOS_LICENSE_SECRET` | HMAC secret for signed offline entitlement tokens (falls back to JWT secret). |
| `FOODPOS_RAZORPAY_KEY_ID` / `_KEY_SECRET` / `_WEBHOOK_SECRET` | Enables hosted checkout + signature-verified webhooks. |
| `FOODPOS_SMTP_HOST` / `_PORT` / `_USER` / `_PASS` / `_FROM` | Outbound e-mail (welcome, verification, receipts, renewal reminders). When unset mail is skipped (dev tokens echoed). |
| `FOODPOS_APP_BASE_URL` | Console/portal origin used in e-mail links. |

The pro plan and an active subscription for the legacy demo org (`org-01`) are
ensured on every server start (`ensureDefaultTenant`), so existing terminals
keep their entitlement.

## API surface (new)

Public:
- `POST /api/v1/auth/register` — org self-registration → returns owner token,
  `org_code`, first outlet, initial admin PIN (shown once), plan/trial.
- `POST /api/v1/auth/account/login|refresh|logout` — owner email/password.
- `POST /api/v1/auth/device-options {org_code}` — outlets + staff for POS PIN
  login (replaces the old global public staff listing; legacy `GET /staff` and
  `GET /outlets` still work and default to the demo org).
- `POST /api/v1/admin/login|refresh|logout` — superadmin.

Owner (scope: owner, `/api/v1/saas`):
- `GET /me`, `GET /org` (org + subscription + outlets + staff + invoices + events)
- `POST /outlets` (plan-limited), `POST /staff` (org/outlet scoped)
- `POST /subscription/cancel`

Superadmin (scope: admin, `/api/v1/admin`):
- `GET /orgs?status=`, `GET /orgs/{id}` (detail)
- `POST /orgs/{id}/activate` `{method: bank|upi|razorpay, period_days, amount_paise, reference, notes}` → records a paid invoice (with GST 18%) and opens the period
- `POST /orgs/{id}/extend {days}`, `/suspend`, `/cancel`
- `POST /orgs/{id}/checkout` → Razorpay hosted order (requires gateway keys)
- `GET /invoices/{id}/pdf`, `GET /stats`

Account lifecycle (public or owner):
- `POST /auth/account/forgot|reset|verify` — password reset + e-mail
  verification via rotating single-use tokens (dev fallback echoes the token
  when SMTP is off)
- `POST /saas/org/rotate-code` — revoke + issue a fresh org code
- `GET /saas/invoices/{id}/pdf` — generated invoice PDF

Webhooks:
- `POST /api/v1/webhooks/razorpay` (public) — HMAC-SHA256 verified; on
  `payment.captured` opens the paid period + records the invoice.

SaaS invoices carry GST: `gst_percent` (18%), `tax_paise` and `gross_paise`
(amount + tax = what the customer pays). Razorpay checkouts charge the gross;
the webhook extracts the taxable base (÷1.18).

## CLI

```powershell
# Manual billing without the console UI:
cd backend
go run ./cmd/admin list
go run ./cmd/admin show org-XXX
go run ./cmd/admin activate org-XXX -method bank -days 30 -ref "NEFT TXN" -note "Pilot month"
go run ./cmd/admin suspend org-XXX -note "unpaid"
go run ./cmd/admin stats
```

## Daily billing job (cron)

```powershell
go run ./cmd/billing
```
Sweeps: trial → expired at trial end; active → past_due after period end;
past_due → suspended after 3 extra days. Every transition writes an
`org_events` row. Schedule daily (e.g. cron/Windows Task Scheduler).

## Entitlement enforcement

- **Server:** paid writes (POS write group + owner outlet provisioning) return
  `402 subscription_expired` unless the org is trial/active. Reads stay open.
  Every write that passes the gate is recorded in `audit_log` with org/outlet
  attribution (audit middleware).
- **Idempotency keys** are namespaced per org (sha256(org:key)) so tenants can
  never replay each other's offline ops.
- **By-id routes** (`GET /orders/{id}`, `GET /menu/{id}`, `PATCH /kots/{id}`,
  `GET /outlets/{id}`) verify the resource belongs to the caller's outlet.
- **Staff caps:** `plans.max_staff` (like `max_outlets`) is enforced when
  creating staff from the POS or owner APIs.
- **Offline terminals:** the login response carries `entitlement
  {status, valid_until}` (valid_until = period/trial end + 7-day grace) plus
  `entitlement_token` — an HMAC-signed token (`internal/license`) the client
  can verify without trusting its own clock. Enforcing a read-only lock in the
  Flutter POS app from that token is the remaining client-side step; the
  server denial on the next sync remains the enforcement point and queued
  payment ops surface — never auto-drop.

## Tests

- `internal/api/saas_integration_test.go` — registration → trial ordering,
  superadmin activate → invoice + active, suspend → 402 writes/200 reads,
  cross-org login + manager-PIN isolation, refresh preserves tenant.
- `internal/license` — signed entitlement round-trip + tamper/wrong-secret.
- `internal/billing` — invoice PDF rendering, Razorpay signature verify.
- Requires PostgreSQL (`FOODPOS_TEST_DSN`). Unit path:

```powershell
go vet ./... ; go build ./... ; go test ./internal/service ./internal/license ./internal/billing
```

## Realtime resume (SSE)

Events carry per-outlet sequence numbers (`id:` lines). The Flutter client
tracks the last id and reconnects with `last_event_id`; the hub replays newer
events from its in-memory ring (cap 1000/outlet) before going live. This is a
**single-instance** assumption — with multiple server instances the ring would
move to shared storage (queue/Redis) — documented in the architecture notes.

## Known follow-ups

1. Owner + superadmin web console (API-first — endpoints are ready; the
   portal app was deferred again).
2. SMTP e-mail templates polish + transactional delivery provider option;
   e-invoice PDF layout polish (the generator is intentionally minimal).
3. Auto-verified UPI food payments: optional hosted payment-link integration
   behind the gateway seam; needs PSP merchant keys + an offline-first policy
   decision (manual-confirm tender remains the default).
