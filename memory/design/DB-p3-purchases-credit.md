# Design Brief: P3 — Purchases, Stock Log, Customer Credit
- PRD ref: FR-I1, FR-I2, FR-C1
- Status: implemented (2026-09-07)

## Contracts
- Tables added: `customer_credit_log` (audit of credit movements); `refresh_tokens` (see DB-p5-security).
- Tables extended: none (purchases/suppliers tables existed).
- Endpoints:
  - `POST /suppliers` `{name, mobile, email?, category?}` → 201 Supplier | 400 invalid_supplier
  - `POST /purchases` `{invoice_no, supplier_id?, status: paid|pending, total_paise, items:[{inventory_item_id, name?, qty, unit_cost_paise}]}` → 201 Purchase
    - idempotent (Idempotency-Key); per line: stock += qty (clamped by DB), cost updated, `stock_adjustments` row "Purchase <invoice>"; pending → supplier.outstanding += total; all inside one txn; unknown item → 400 invalid_item
  - `PATCH /purchases/{id}` `{status}` → paid→pending is 409 invalid_state; pending→paid reduces supplier outstanding (MAX(0, …))
  - `GET /inventory/{id}/adjustments?limit=` and `GET /inventory/adjustments?item_id=` → stock audit log
  - `POST /customers/{id}/credit` `{kind: sale|settlement, amount_paise>0, reason}` → updated Customer
    - settlement > outstanding → 400 settlement_exceeds_outstanding; empty reason → 400 missing_reason; idempotent
  - `GET /customers/{id}/credit-log` → audit entries
- WS events: none new.
- State machines touched: purchase status paid↔pending (paid is terminal for backward transitions).

## Invariants (testable)
- I1: purchase line posts stock intake and an adjustment audit row in the same txn.
- I2: pending purchase increases supplier outstanding by total; settle reduces it, never below 0.
- I3: paid purchase cannot revert to pending (409).
- I4: credit settlement cannot exceed outstanding (400) and both movements are logged with actor + reason.
- I5: purchase create and credit booking are idempotent under replay.

## Money
- total_paise, amount_paise, unit_cost_paise: paise ints. outstanding: paise int.

## Edge cases
- Purchase with supplier_id not in outlet → 400 invalid_supplier.
- Purchase line qty 0 → skipped (no stock movement).
- Credit booking for unknown customer → 404.

## Test plan
- Integration: TestPurchasesAndStock (intake, log, outstanding lifecycle, 409), TestCustomerCredit (sale, over-settle 400, settle, missing reason 400, log length).
- Verified: `go vet/test/build` green.

## Open questions
- None blocking; purchase line items intentionally live in `summary` + stock log (no purchase_items table) — revisit if per-line reporting is needed.
