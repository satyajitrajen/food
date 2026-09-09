# Project State (updated: 2026-09-07)

## Now
App-vs-API coverage audit (findings/2026-09-07-app-api-coverage.md) fully
complete — every W-item and B-item fixed and verified:
- B1 inclusive GST (migration 003, ApplyBilling extraction, Dart mirror) — D-014
- B2 server-side manager PIN gates on refund / cancel-after-KOT / big
  discounts — D-015 (manager dialog now returns the PIN, threaded through ops)
- B3 PATCH /staff + StaffAdminScreen; W2 MenuAdminScreen (+ true partial PATCH
  /menu/{id} after an FK footgun, D-016); W4/W5 inventory add, supplier add,
  purchase intake + mark paid; W6 credit-log; W7 stock log; W8 server
  Z-report in close-shift; W9 server splits in reports; W11 add table;
  B4 derived CGST/SGST labels.
All gates green: `go vet/test/build` (new: TestManagerGates,
TestInclusiveGSTOrder, TestVerifyManagerPin, TestOrderDefaultsFromSettings,
TestWsTicket), `flutter analyze` 0 issues, `flutter test` 27/27 (new
pin_vault_test); live-server pass covering every new surface + Dart api_smoke
PASSED. Auth hardening done: offline PIN fallback is a salted-hash PinVault
(D-017, no plaintext on real terminals) and /ws connects via single-use
tickets instead of the raw JWT (D-018). Remaining deferred by design:
split-tender UI (Q-1), printer hardware validation (Q-4).

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
- SQLite pure-Go driver (modernc.org/sqlite); `MaxOpenConns(1)` + WAL; keep it. Saturates ~130 order-flows/s (≈520 write reqs/s).
- chi's middleware package collides with internal/middleware — alias chi's as `chimw`.
- Offline writes: apply locally → `SyncEngine.push` → NetworkException enqueues (persisted FIFO, op id = Idempotency-Key); 4xx drops + surfaces. Ids remap via idmap on ack (D-008/D-010).
- MockClient-based engine tests must route handlers through `api.request` or the network path is untested.
- `build/`, platform dirs are generated — never edit.
