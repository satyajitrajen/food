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
| `FOODPOS_SMTP_*` | (Future) renewal/reminder e-mails — not yet wired; billing job logs. |

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
- `POST /orgs/{id}/activate` `{method: bank|upi|razorpay, period_days, amount_paise, reference, notes}` → records a paid invoice and opens the period
- `POST /orgs/{id}/extend {days}`, `/suspend`, `/cancel`
- `GET /stats`

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
- **Offline terminals:** the login response carries `entitlement
  {status, valid_until}` (valid_until = period/trial end + 7-day grace). A
  signed offline-license token + read-only lock on the Flutter side is a
  planned follow-up; today the server denial on the next sync is the
  enforcement point and queued payment ops surface — never auto-drop.

## Tests

- `internal/api/saas_integration_test.go` — registration → trial ordering,
  superadmin activate → invoice + active, suspend → 402 writes/200 reads,
  cross-org login + manager-PIN isolation, refresh preserves tenant.
- Requires PostgreSQL (`FOODPOS_TEST_DSN`). Unit path:

```powershell
go vet ./... ; go build ./... ; go test ./internal/service
```

## Known follow-ups (not in this pass)

1. `internal/billing` gateway interface + Razorpay adapter/webhooks.
2. E-mail (SMTP) for welcome/expiry/receipts; templates.
3. Signed offline license token + Flutter read-only lock & license banner.
4. Flutter org-code bootstrap UI (POS app still uses the legacy demo-org path
   which remains fully compatible).
5. Idempotency-key namespacing per org; `audit_log` org/outlet columns.
6. Owner + superadmin web console (API-first — endpoints are ready).
