# Design Brief: SaaS product fixes — security gates, plan catalog, lead capture

- PRD ref: docs/agents.md Review ledger findings/2026-09-13-product-review.md (S1–S4, M1–M3, L1–L2)
- Status: approved
- Date: 2026-09-13

## Contracts

### Environment & security (S3, S4)
- `config.Config` gains `Env string` (`FOODPOS_ENV`, default `development`) and `Dev bool`
  (`FOODPOS_DEV=1` explicit, or default true only when Env != production).
- `Config.Validate() error`: in production requires `FOODPOS_JWT_SECRET` set and not the dev
  default; forces `CORSOrigins * → ""` (same-origin) in production.
- `handleForgotPassword`: SMTP off → `FOODPOS_DEV=1` echoes token (200); otherwise 503
  `mail_unconfigured`. main.go logs a warning when production runs without SMTP.

### Rate limiting (M1)
- `middleware.ClientIP(r)`: uses first `X-Forwarded-For` entry only when `RemoteAddr` host is
  loopback or RFC1918 private (reverse proxy on same host / docker bridge); else RemoteAddr.
- `RateLimit` keys on ClientIP. Invariant: direct connections are unaffected; spoofed XFF from
  a non-trusted source IP is ignored.

### Plan catalog (S1)
- `plans` seeded (upsert by code) from the landing catalog:
  | code | name | monthly paise | interval | outlets | staff |
  |------|------|--------------|----------|---------|-------|
  | starter | Starter Café | 99900 | 30 | 1 | 10 |
  | pro | Pro Dining | 199900 | 30 | 5 | 20 |
  | chain | Multi-Outlet Chain | 399900 | 30 | 100 | 500 |
  | starter-annual | Starter Café (annual) | 958800 | 365 | 1 | 10 |
  | pro-annual | Pro Dining (annual) | 1918800 | 365 | 5 | 20 |
  | chain-annual | Multi-Outlet Chain (annual) | 3838800 | 365 | 100 | 500 |
  - trial_days 14 for ALL variants (a 0-day trial would be expired instantly by
    the billing cron; annual is just a longer billing interval chosen at signup).
- `RegisterOrgReq.PlanCode` (optional, default `pro`); unknown code → 400 `invalid_plan`.
- `store.RegisterOrg` gains planCode param; `SeedDefaultPlan` → `SeedDefaultPlans` (idempotent
  upserts; callers: server boot, cmd/billing, register).

### Leads (S2)
- Migration 009: `leads(id, restaurant_name, contact_name, phone, city, outlet_format,
  plan_interest, source, status default 'new', created_at)`.
- `POST /api/v1/leads` (public, registerLimit 10/min): restaurant_name ≥ 2 chars, phone
  10–12 digits after stripping non-digits. Returns `{id}`.
- `GET /api/v1/admin/leads` (scope admin, newest first, limit 200).
- Landing DemoModal submits to the API; on failure falls back to WhatsApp deep link.
  WhatsApp number from `VITE_FOODPOS_WHATSAPP` (fallback existing hardcoded).
- Pricing "Choose" buttons navigate to `/console?plan=<code>` (real signup); console
  pre-fills plan_code from the query param.

### Webhook hardening (M2)
- `payment.failed` / `payment.refunded` → `org_events` (`razorpay.payment_failed`,
  `razorpay.payment_refunded`) with payment id/amount. No automatic status flips (cron owns
  the trial/period lifecycle; a single failed capture must not suspend an org).

### Infra (M3) + docs (L1) + client (L2)
- docker-compose: postgres:16-alpine, user/pass `foodpos`, db `foodpos_test` (+ `foodpos`
  via init script) matching the integration-test default DSN.
- GitHub Actions: backend (go vet/test/build vs postgres service), flutter (analyze/test),
  landing (npm ci/build).
- Root README: product + per-workspace commands.
- PosProvider demo seeds wrapped in `kDebugMode`.

## Money
- Plan prices only, integer paise, seeded rows above. No new computed money.

## Invariants (testable)
- I1: forgot-password without SMTP and without FOODPOS_DEV=1 returns 503 and never a token.
- I2: register with `plan_code=chain` yields subscription.plan.max_outlets=100; unknown code → 400.
- I3: POST /api/v1/leads persists a row and rejects short phone (400); 11th request/min → 429.
- I4: clientIPFrom ignores X-Forwarded-For when RemoteAddr is public.
- I5: webhook `payment.failed` adds an org_event and changes no subscription status.

## Edge cases
- XFF list with multiple entries: take first (leftmost, set by outermost trusted proxy).
- Register without plan_code keeps current behavior (pro) — old console versions unaffected.
- DemoModal API failure must not block the WhatsApp fallback path.
- plans upsert must not resurrect manually deactivated plans (is_active forced 1 for
  canonical codes — accepted; superadmin-created extra plans use other codes).

## Test plan
- Unit: middleware clientIPFrom (public/loopback/private × XFF present/absent).
- Integration (needs Postgres; CI): forgot gate, register plan_code, leads create/list,
  webhook failed event.
- Flutter: existing suite must stay green with kDebugMode seed guard.

## Open questions
- None blocking. Annual signup flow: register starts a trial regardless of variant;
  annual invoicing happens at activation (manual/Razorpay) using the plan row's price/interval.
