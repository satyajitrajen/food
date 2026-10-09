# DB: Order GET echoes payment legs (split-payment echo)

Date: 2026-10-10 · Batches 2 of the 2026-10-10 emulator audit fixes · D-021

## Problem

`POST /orders/{id}/pay` books one `order_payments` row per tender leg (split
payments), but the order JSON only carried the scalar `payment_method`
(`'split'` when multiple tenders) — the client could not render
"Paid (Cash) / Paid (Card)" on receipts after a refetch.

## Contracts

- `GET /api/v1/orders/{id}` (and the pay response, which re-reads the order)
  gains an optional `payments` array on the order object:
  `[{"method": "cash", "amount_paise": 20000}, …]`.
- Field type reuses `models.PaymentSplit` (the same shape the pay REQUEST
  takes), so one struct documents both directions.
- `Order.Payments` is `json:"payments,omitempty"`: absent on
  `GET /orders` list rows, on sync/SSE payloads for open orders, and on old
  orders with no legs — additive and backward compatible.
- The scalar `payment_method` remains exactly as stored (`'split'` literal for
  multi-tender bills); nothing existing changes meaning.
- Credit bills echo one leg `{"method": "credit", "amount_paise": <total>}`
  (already booked that way at pay time).

## Invariants

- Echo only: no handler may accept client-supplied `payments` writes; legs
  are created exclusively inside `PayOrder`'s transaction.
- Loaded only on the single-order read path (`store.getOrderQ`); list/report
  queries stay untouched (per-leg joins there are a reports concern, not an
  order-echo concern).
- Leg order is `ORDER BY id`: stable across refetches but NOT insertion order
  (`NewID` is random; `order_payments` has no seq column). Cosmetic for split
  receipts only.

## Money-in-paise

- `amount_paise` is the server-side integer paise (D-001/D-009). Flutter
  converts to rupees once in `dto.dart orderFromApi` (`PaymentLeg.amount`).
- Sum of legs ≤ paid total by construction (PlanPayment enforces coverage);
  a cash over-tender leg is stored net of change.

## Test plan

- Go (`internal/api/payments_echo_integration_test.go`): pay an order with
  two splits → GET order asserts `payments` has both legs (method/amount) and
  `payment_method == 'split'`. Order-insensitive on leg order. Failed RED
  before the store/models change (echo key missing).
- Flutter `test/dto_test.dart`: parses `payments` + `payment_reference`
  (present and absent), scalar `'split'` → label `'Split'`.
- Flutter `test/escpos_test.dart`: split receipt prints one `Paid (method)`
  row per leg plus `Approval: <ref>` when a card leg carries a reference.
- Sync fixtures: no change (`omitempty`; `test/sync_contract_test.dart` does
  not snapshot order JSON keys).
