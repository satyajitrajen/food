# Project State (updated: 2026-09-13)

## Now
Branch `feature/saas-conversion`: SaaS layer complete (org/tenant model, three
token scopes, entitlement 402 gate, Razorpay + manual billing, React landing +
/console embedded in the Go binary). Product review 2026-09-13 found 4 HIGH +
4 MED + 3 LOW issues (findings/2026-09-13-product-review.md) — ALL FIXED same
day per design DB-saas-product-fixes.md:
- Security: reset-token echo gated behind FOODPOS_DEV (503 otherwise);
  FOODPOS_ENV=production requires JWT secret + drops wildcard CORS; rate
  limiting honors X-Forwarded-For only from loopback/private proxies;
  webhook now audits payment.failed/refunded (no status flips — cron owns
  lifecycle).
- Revenue: plan catalog in store/saas.go matches landing (starter/pro/chain
  ± annual, upserted on boot); auth/register accepts plan_code; pricing CTAs
  go to /console/register?plan=…; demo leads persist via POST /api/v1/leads
  (migration 009) and are listable by superadmin; WhatsApp number via
  VITE_FOODPOS_WHATSAPP.
- Infra/docs: docker-compose Postgres (matches test DSN), GitHub Actions CI
  (go vet/test/build + flutter + landing), real README, release Flutter builds
  strip the demo seed dataset (kDebugMode guard).
- Razorpay Subscriptions auto-renew (design DB-razorpay-subscriptions.md):
  migration 010 (plans.gateway_plan_id, org_subscriptions.gateway_subscription_id
  /gateway_status), billing gateway CreatePlan/CreateSubscription/addon/cancel
  with injectable base URL, webhook handles subscription.charged (renews +
  invoices, idempotent per payment id) / authenticated / activated / pending /
  halted / cancelled / completed, owner POST /api/v1/saas/subscription/razorpay
  + console "Enable auto-renew" hosted checkout, ₹101 registration fee as
  first-cycle add-on (FOODPOS_RAZORPAY_REGISTRATION_AMOUNT_PAISE). Live keys
  in gitignored .env only; rotate KEY_SECRET (it was pasted in chat).
Gates green: `flutter analyze` 0 issues, `flutter test` 34/34, `go vet` clean,
`go build ./...` OK, DB-free unit tests pass (clientIP/rate-limit, Razorpay
subscription flow); backend integration tests (incl. saas_renew_test.go) run
in CI against the compose Postgres (no local Postgres/Docker on this machine).
## Next (ordered)
1. Deploy: set FOODPOS_ENV=production + strong FOODPOS_JWT_SECRET + SMTP +
   FOODPOS_RAZORPAY_WEBHOOK_SECRET on the live server; configure the
   subscription.* + payment.* webhook events in the Razorpay dashboard.
2. Pilot hardening: SSE Last-Event-ID resume (Q-5), split-tender UI (Q-1),
   printer hardware validation (Q-4).

## Done
- [x] Phase 0: 40+ HIGH/MED fixes — analyze clean, tests green
- [x] Phase 1: backend scaffold, auth, catalog/order/KOT/payment/shift/
      expense/customer/inventory APIs, SSE hub, idempotency
- [x] Phase 2/4: Flutter ApiClient + dto (paise at edge) + outbox sync
      engine (restart-safe FIFO replay, idmap) + cache-first hydrate +
      SSE realtime + kitchen display live — design: DB-p2p4-flutter-api-sync
- [x] Phase 3: suppliers/purchases writes (+stock intake), stock log read,
      customer credit sale/settlement + log (FR-C1) + settle UI —
      design: DB-p3-purchases-credit
- [x] Phase 5: refresh-token rotation (hashed, single-use), auth rate
      limits, public GET /staff, ESC/POS printer hooks, load test
      (cmd/loadtest), migrations 002 — design: DB-p5-security-print-load

## Next (ordered)
1. Pilot hardening (optional): SSE Last-Event-ID resume (Q-5), split-tender
   payment UI (Q-1/P3 deferred), per-line purchase reporting if needed.
2. Printer hardware validation against real ESC/POS models (Q-4).
3. Deployment: TLS via reverse proxy, prod JWT secret, backup/restore
   runbook dry-run.

## Verified commands
- backend: `cd backend && go vet ./... && go test ./... && go build ./...`
- backend smoke: `$env:FOODPOS_SEED='1'; go run ./cmd/server` (see backend/README.md)
- load test: `go run ./cmd/loadtest -base http://localhost:8080 -rps 50 -duration 20s`
- flutter API smoke: start server, then `dart run tool/api_smoke.dart http://localhost:8080`
- flutter: `flutter analyze` (0 issues) + `flutter test` (27 pass)
- run app against backend: `flutter run --dart-define=FOODPOS_API_URL=https://food.nexorytechnologies.com`

## Gotchas (hard-won)
- `firstWhere` without `orElse` was the #1 crash class — now `.where(...).firstOrNull` everywhere; keep the pattern.
- Money is paise ints in Go; Dart converts only in `core/api/dto.dart` (D-009); display edge uses `roundMoney`.
- GST base = net + service charge (D-005); `ApplyBilling` in `internal/service/service.go` is the single source of truth for billing math.
- Refunds are tender-aware: `refunds_cash` leaves the drawer, `refunds_digital` doesn't (D-004).
- Postgres via the pgq driver (rewrites SQLite-style SQL); integration tests
  need a live Postgres on localhost:5432 (no compose/CI yet — finding M3).
- chi's middleware package collides with internal/middleware — alias chi's as `chimw`.
- Offline writes: apply locally → `SyncEngine.push` → NetworkException enqueues (persisted FIFO, op id = Idempotency-Key); 4xx drops + surfaces. Ids remap via idmap on ack (D-008/D-010).
- MockClient-based engine tests must route handlers through `api.request` or the network path is untested.
- `build/`, platform dirs are generated — never edit.
