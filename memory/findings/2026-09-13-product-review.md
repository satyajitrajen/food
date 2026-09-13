# Findings: Product Review (SaaS-conversion branch)

- Date: 2026-09-13
- Scope: whole product — Flutter client (lib/), Go backend (backend/), landing+console (landing/), plus the uncommitted WIP diff (11 files).
- Evidence: fresh greps/reads cited per item; gates run this session: `flutter analyze` 0 issues, `flutter test` 34/34 pass, `go vet` clean, `go build ./...` OK, `go test ./...` → unit packages pass, integration suite skipped (needs Postgres, see M3).
- 2026-09-13 (later same day): ALL findings fixed in the working tree — design
  brief memory/design/DB-saas-product-fixes.md, verification gates re-run green
  (integration tests now run in CI against the compose Postgres).

## HIGH

### S1 · Landing pricing does not match any sellable plan — status: FIXED (2026-09-13)
- landing/src/components/Pricing.tsx:48,110,164 advertises 3 tiers (Starter ₹999 / Pro ₹1,999 / Chain ₹3,999, yearly variants) and every "Choose plan" CTA opens DemoModal.
- Backend has exactly one plan: `pro` ₹1,499/mo, 5 outlets, 20 staff, 14d trial (backend/internal/store/saas.go:274-278). No endpoint or code path maps a chosen tier to a purchase.
- Fix: seed the three advertised plans (or align landing to the single Pro plan) and thread a plan code through `auth/register` → subscription.

### S2 · Demo-request funnel captures nothing — status: FIXED (2026-09-13)
- landing/src/components/DemoModal.tsx:59-65 submit is a `setTimeout` simulation with a fabricated `DEMO-<n>` id; nothing is persisted or sent. Only outbound path is a hardcoded WhatsApp deep link `wa.me/919822000000` (DemoModal.tsx:261, Footer.tsx:104).
- Every marketing CTA routes here, so leads are lost server-side.
- Fix: add a leads endpoint (or reuse `auth/register` intent), persist submissions, and make the WhatsApp number/number-format configurable.

### S3 · Password reset returns the reset token in the API response when SMTP is unconfigured — status: FIXED (2026-09-13)
- backend/internal/api/handlers_saas_extra.go:84 returns `Token` with "SMTP disabled — dev reset token returned"; models/saas.go:235-237. Guarded only by mailer `Enabled()`, i.e. an ops accident away from owner-account takeover of any org.
- Fix: gate the echo behind an explicit dev flag (e.g. `FOODPOS_DEV=1`); return 503 "mail unavailable" otherwise, and add a startup warning when SMTP is off in prod.

### S4 · Insecure production defaults — status: FIXED (2026-09-13)
- backend/internal/config/config.go:40 `FOODPOS_JWT_SECRET` defaults to `"dev-secret-change-me"`; config.go:56 `CORSOrigins` defaults to `*`.
- Fix: fail fast (or loud warning) when JWT secret is unset outside dev; default CORS to empty (same-origin reverse proxy) instead of `*`.

## MED

### M1 · Auth rate limiting keyed on RemoteAddr only — status: FIXED (2026-09-13)
- backend/internal/middleware/ratelimit.go:48-50. Deployment plan is TLS via a reverse proxy (PROJECT_STATE Next #3); behind it every client shares one IP → either global lockout or ineffective limiting.
- Fix: parse X-Forwarded-For/X-Real-IP from a trusted-proxy allowlist before falling back to RemoteAddr.

### M2 · Billing lifecycle has no renewals and a single webhook event — status: FIXED (2026-09-13, both halves)
- Webhook handles only `payment.captured` (backend/internal/api/handlers_saas_extra.go); no refund/failure events, no auto-renew. cmd/billing can only expire/suspend and send reminders when SMTP is configured; runbook documents manual superadmin activation as the primary flow.
- Fix: full Razorpay Subscriptions auto-renew per design DB-razorpay-subscriptions.md (migration 010, gateway plan/subscription/addon/cancel APIs, `subscription.charged` renews + invoices with per-payment idempotency, `cancelled`/`completed` lapse the sub, owner "Enable auto-renew" hosted checkout in the console, registration fee ₹101 as first-cycle add-on); payment.failed/refunded audited.

### M3 · Backend integration tests need a Postgres that nothing in the repo provisions — status: FIXED (2026-09-13)
- `go test ./...` fails on a clean machine: 22 integration tests dial localhost:5432 (backend/internal/api/integration_test.go:142 et al.). No docker-compose, no CI pipeline anywhere in the repo.
- Fix: docker-compose with Postgres + document `FOODPOS_DSN` for tests; add CI running vet/test/build + flutter analyze/test.

### M4 · memory/PROJECT_STATE.md was stale (pre-SaaS, dated 2026-09-07) — status: FIXED (this session)
- Now/Done refreshed with the SaaS-conversion state and gotchas updated SQLite→Postgres (backend/internal/db/db.go pgq rewrites SQLite SQL for Postgres).

## LOW

### L1 · README is default Flutter boilerplate — status: FIXED (2026-09-13)
- README.md has zero product content for a 3-workspace monorepo (app/backend/landing). Fix: short README with what FoodPOS is, per-workspace run commands (PROJECT_STATE "Verified commands" is a good seed).

### L2 · Demo/demo-PIN data ships inside the app binary — status: FIXED (2026-09-13)
- PosProvider seed dataset with fabricated staff, GSTIN, plaintext demo PINs (lib/providers/pos_provider.dart:1163-1212, 1454-1467, 3041-3168) — blanked in API mode, but still present; only matters if a terminal runs with `apiEnabled:false` (main.dart:32 currently hardcodes true).
- Fix: strip seeds from release builds (const-guard behind a debug define).

### L3 · WIP diff (uncommitted, 11 files) reviewed — status: FIXED (in working tree, uncommitted)
- Overflow/ellipsis layout fixes across 9 screens: sound, no logic changes.
- dto.dart:176-177 adds `kitchen` role mapping — real bug fix: kitchen staff previously fell back to `waiter` (wrong shell/UI); new tests in test/dto_test.dart:100-116 cover it.
- guest_details_dialog.dart:35-39,119-122 waiters can only assign themselves — client-side only; server already validates staff↔org, acceptable.
- pos_menu_screen.dart:282-313 menu card is now tappable via InkWell→`_handleItemTap` (method exists, pos_menu_screen.dart:28); indentation drifted inside the re-wrap (analyze is clean; cosmetic only).
- Gates: flutter analyze 0 issues, flutter test 34/34, go vet/build OK.

## Validated strengths (no action)
- Offline-first writes: outbox FIFO + idempotency keys + id remap, restart-safe (test/sync_engine_test.dart).
- Entitlement enforcement is server-side (402 `subscription_expired` on paid writes, backend/internal/api/entitlement.go:28-37) with offline HMAC entitlement tokens on terminals.
- Tenant isolation in middleware (StaffTenant rejects cross-org outlet ids); RBAC enforced server-side (RequireRole/DenyRoles, internal/api/auth.go:206-233).
- Money in paise at the API edge only; single billing-math source (ApplyBilling, internal/service/service.go).
- SSE realtime with single-use 60s tickets instead of URL JWTs.
- Landing /console wires real `POST /api/v1/auth/register` (14-day trial) — the SaaS signup path exists and works; the gap is the marketing CTAs (S1/S2), not the console.
