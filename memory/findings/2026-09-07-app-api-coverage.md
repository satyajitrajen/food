# Findings — App Needs vs API Coverage (2026-09-07)

Question: "do we have everything in the API that the app needs?"
Method: PRD FR list (docs/PRD.md) × app screens/providers × API surface (server.go).
Status: wired | api-ready-no-ui | missing-both | deferred

All findings in this ledger are now **fixed and verified** (same session):
gates green (`go vet/test/build`, `flutter analyze` 0 issues, `flutter test`
24/24), plus a live-server pass covering every new surface (staff PATCH, menu
CRUD, inventory/supplier/purchase writes, table create, inclusive GST order,
all three manager gates, verify-manager-pin, Dart api_smoke).

## Verdict
Everything on the PRD's core money path (order → KOT → pay → refund → shift →
reports) is served by the API and wired. The gaps are admin/back-office surfaces
and two business-rule holes. W1 + W10 fixed 2026-09-07 (see items). Remaining
W2–W9, W11 and B1–B4 were completed in the same session (see per-item status).

## A. API exists — app has no consumer (wiring gaps)
- W1 `POST /auth/verify-manager-pin` — FR-A3 manager gates (refund, discount,
  cancel-after-KOT, payment/void) verified PINs against the **local seed list**
  (pos_provider.verifyManagerPin), not the server's bcrypt hashes.
  → **fixed**: `ApiClient.verifyManagerPin` + async provider check; server is
  authoritative online, local staff list remains the offline/401 fallback.
  Dialog shows a progress state while verifying. Test:
  `TestVerifyManagerPin`.
- W2 `PATCH /menu/{id}` — FR-M1 availability toggle has no UI; menu is
  read-only in the app (create/patch/delete all unused).
  → **fixed**: `MenuAdminScreen` (More hub, manager-gated): add/edit/delete +
  availability switch via new `menu.create/update/delete` outbox ops with
  server-truth upserts. Backend PATCH made a true partial patch (D-016) after a
  partial body was found to wipe name/category_id (FK footgun).
- W3 `POST /staff` — PRD Admin capability "staff management"; no staff admin
  screen exists.
  → **fixed**: `StaffAdminScreen` (More hub, manager-gated) + `staff.create` /
  `staff.patch` ops: add staff, change role, activate/deactivate, reset PIN.
- W4 `POST /inventory` — no add-inventory-item UI (FR-I1 create half missing).
  → **fixed**: add-item action in the inventory screen (`inventory.create` op).
- W5 Suppliers/purchases: `GET/POST /suppliers`, `GET/POST /purchases`,
  `PATCH /purchases/{id}` — inventory screen tabs are read-only; no supplier
  add, no purchase intake, no mark-purchase-paid UI (FR-I2).
  → **fixed**: Add Supplier FAB, Purchases tab with Record Purchase dialog
  (per-line stock intake) and Mark Paid action (`supplier.create`,
  `purchase.create`, `purchase.patch` ops).
- W6 `GET /customers/{id}/credit-log` — credit history has no UI (FR-C1 audit).
  → **fixed**: "Credit history" action per customer; server ledger fetched
  directly with the sync id-map translation; offline shows a clear notice.
- W7 `GET /inventory/{id}/adjustments` (+ list form) — app kept a local-only
  stock log; server audit trail unused.
  → **fixed**: "Stock Log" tab in the inventory screen fetching the server
  adjustments log (local log remains the offline fallback; pull-to-refresh).
- W8 `GET /reports/shift/{id}/zreport` — close-shift computed
  expected/counted/variance locally (FR-R3 server truth unused).
  → **fixed**: after close, the dialog fetches the server Z-report (local
  shift id → server id via the sync id map) and shows totals/counted/variance.
- W9 `/reports/dashboard` `sales_by_type`, `sales_by_tender`, `top_categories`
  — fetched but not parsed; reports screen derived splits from cached orders
  only, so multi-terminal numbers diverged (FR-R2).
  → **fixed**: `DashboardStats` parses the three splits; the reports screen
  prefers server values with the local derivation as offline fallback.
- W10 Settings defaults are dead config on BOTH sides: backend hardcodes
  `taxPercent=5.0` when `OrderCreate.tax_percent` is absent
  (handlers_orders.go:107-110) and never reads settings GST/service/packaging/
  delivery defaults; frontend never sends them. Changing GST to 12% in settings
  does not change billing. API already supports the fix (`tax_percent` on
  create, charges on `OrderPatch`).
  → **fixed (GST + packaging/delivery)**: order create now resolves the GST
  percent from the outlet's settings (explicit `tax_percent` still wins) and
  auto-applies packaging (takeaway+delivery) / delivery (delivery) charge
  defaults; the frontend mirrors the same defaults on local order creation so
  offline orders bill identically. Service-charge percent default remains
  manual (it is a percent; the order model stores absolute paise — noted as
  future work with inclusive GST, B1). Tests: `TestOrderDefaultsFromSettings`;
  `TestDiscountClampEndpoint` updated (charges survive a 100% subtotal
  discount per FR-O3).
- W11 `POST /tables` — no add-table UI (settings floors panel is read-only).
  → **fixed**: "Add Table" action in the settings floors panel (`table.create`
  op; manager-gated UI).

## B. Missing in API and app (need design + build)
- B1 **Inclusive GST** — FR-O3 promises it; `is_gst_inclusive` is stored in
  settings on both sides but neither `ApplyBilling` (service.go) nor
  `order_model.dart` implemented inclusive extraction.
  → **fixed**: migration 003 `orders.is_tax_inclusive`; create inherits the
  flag from settings; `ApplyBilling` extracts tax (base·pct/(100+pct)) and
  keeps the grand total at menu price + charges; `order_model.dart` mirrors
  it for offline bills. Tests: `TestApplyBillingInclusiveGST`,
  `TestInclusiveGSTOrder`. Decision D-014.
- B2 **Server-side manager gates** — FR-A3 thresholds were enforced only in UI.
  → **fixed**: `manager_pin` required server-side for refunds (always),
  cancelling KOT-sent items (explicit + qty→0 removal) and discounts above
  20%/₹500 — verified against bcrypt manager/admin PINs, 403 otherwise. The
  manager dialog returns the PIN and it rides the outbox payloads. Tests:
  `TestManagerGates`. Decision D-015.
- B3 **PATCH /staff** — admin could not edit/deactivate staff server-side.
  → **fixed**: `PATCH /staff/{id}` (manager-gated; name/role/mobile/avatar/
  is_active/PIN reset) + `store.UpdateStaff` + `StaffAdminScreen`.
- B4 Receipt labels hardcoded "CGST/SGST 2.5%".
  → **fixed**: bill preview, payment-success receipt and the settings panel
  now derive the half-rate labels from the real `taxPercent`.

## Deferred by design (no action)
- Split tender UI (API `splits[]` ready) — PRD Phase 3 "later", tracked Q-1.
- Printer hardware (ESC/POS hooks local by nature), loyalty, multi-currency —
  PRD out-of-scope.

## Wired and verified (no action)
Auth/refresh/roles, outlets/staff reads, tables + move/merge/unmerge, menu read,
orders/items/qty/cancel, KOT fire + FSM board, pay/refund, shifts
open/close/cash-move/history, expenses create/delete, customers create +
credit book/settle, stock adjust, settings read/update (manager), SSE realtime,
offline outbox + idempotent replay.
