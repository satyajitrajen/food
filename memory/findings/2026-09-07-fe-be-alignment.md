# Findings — Frontend/Backend Alignment Cross-Check (2026-09-07)

Cross-checked: routes (server.go) vs op registry (pos_provider.dart) vs DTOs (dto.dart)
vs wire models (models.go) vs SSE hub events vs request/response shapes.
Status per item: open | fixed | wontfix

## HIGH
- F-A1 **Menu never hydrates from the API.** Frontend read `menu['menu']`
  (pos_provider.dart:333); backend returns key `menu_items`
  (handlers_catalog.go:198). In API mode the POS menu, cart, KOT and billing all
  stayed on local seed data. → **fixed**: frontend now reads `menu_items`.
- F-A2 **`PUT /settings` always failed.** `settingsToApi` (dto.dart) omits
  `outlet_id`; backend decoded into `models.Settings` and upserted keyed on the
  (empty) `outlet_id` → FK violation `settings.outlet_id REFERENCES outlets(id)`
  (001_init.sql:286) → 500; op dropped; settings changes never persisted.
  → **fixed**: `handlePutSettings` resolves the outlet via `outletScope`
  (query param/JWT claim) when the body omits it, 400 if no scope at all.
  Regression test: `TestSettingsUpsertResolvesOutlet` (integration_test.go).

## MED
- F-A3 `order.patch` `customer_name` ignored by backend. `setGuestDetails`
  (pos_provider.dart) sends it, but `models.OrderPatch` had no CustomerName
  field → guest-name edits never persisted or replicated to other terminals.
  → **fixed**: `OrderPatch.CustomerName` added; applied in `store.PatchOrder`.
- F-A4 Idempotency gaps on the backend. Frontend sends `Idempotency-Key` for
  `expense.create` but `handleCreateExpense` didn't use `withIdempotency` →
  duplicate expense rows possible when a response is lost and the outbox
  replays. `shift.open` and `kot.fire` were likewise unguarded (replay → noisy
  409 even though the write succeeded).
  → **fixed**: `withIdempotency` wraps `handleCreateExpense`, `handleOpenShift`,
  and `handleFireKOT`; replays now return the original response.

## LOW
- F-A5 Role gating mismatch: Flutter settings screen lets any staff save;
  backend `PUT /settings` requires manager → 403 + sync error for
  cashier/waiter. → **fixed**: `updateSettings` only pushes for manager/admin
  role (local-only otherwise), matching the server contract.
- F-A6 Docs drift (docs/ARCHITECTURE.md §4): documented but not implemented —
  `PATCH /staff/{id}`, `GET /customers/{id}`, `GET /inventory/low`,
  `GET /reports/sales`; implemented but undocumented — `POST /auth/logout`,
  credit-log, stock adjustments log, `PATCH /purchases/{id}`.
  → **fixed**: §4 table rewritten to match the implemented API.
- F-A7 Backend surface with no Flutter consumer (screens are local-only, so
  dashboards/reports diverge across terminals): `/reports/dashboard`,
  `/reports/shift/{id}/zreport`, `POST /staff`, menu CRUD, `GET /orders/{id}`,
  `GET /shifts`, credit-log, stock adjustments log, `POST /inventory`,
  `POST /suppliers`, `POST /purchases`, `PATCH /purchases/{id}`,
  `/auth/verify-manager-pin` (frontend uses a local PIN check instead).
  → **partially fixed**: provider now hydrates `GET /reports/dashboard` into
  `serverDashboard` (new `DashboardStats` model) and `GET /shifts` into
  `_shiftHistory`; the dashboard screen prefers server KPIs with local fallback.
  Remaining consumers (z-report, staff/menu CRUD writes, supplier/purchase
  writes, credit/stock logs) → **wontfix for now**: they need dedicated UI
  feature work, tracked for a future phase.
- F-A8 Dead code: `handleLogin`/`handleRefresh` checked `err` after
  `auth.NewRefreshToken()` which returns no error. → **fixed**.
- F-A9 `hydrateOutlet` aborted all remaining reads if any single read threw
  (e.g. a 404 on settings skipped shifts → purchases).
  → **fixed**: per-section `_tryRead` containment; only a network outage
  aborts the batch.

## Confirmed aligned (no action)
- All route paths/methods match the op registry; outlet scoping via
  `?outlet_id=` matches; outlet ids out-01/out-02 match seed data.
- SSE event names (`order.updated`, `kot.created`, `kot.updated`,
  `table.updated`, `shift.updated`) and `Event{type,payload}` envelope match the
  frontend `_applyRealtimeEvent` switch; token-in-query auth matches the hub.
- Money convention (paise int over the wire, rupees double in Dart) consistent
  via dto.dart; snake_case payload keys match Go JSON tags across orders, items,
  KOT, shifts, cash moves, expenses, customers, credit, stock, tables.
- KOT FSM (new→preparing→ready→served, cancel-before-served) matches the kitchen
  board buttons; `item.qty` quantity 0 → backend cancels with audit reason.
- Payment/refund request shapes match (`method` cash|upi|card,
  `amount_received_paise`, `amount_paise/reason/is_full_refund/mode`), refund
  response `order` key read correctly; token/refresh response keys match
  `_storeSession`.

## Verify (post-fix)
- backend: `go vet ./... && go test ./... && go build ./...` — green
  (includes new `TestSettingsUpsertResolvesOutlet`).
- flutter: `flutter analyze` 0 issues; `flutter test` 24/24 pass.
