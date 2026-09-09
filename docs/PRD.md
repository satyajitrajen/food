# FoodPOS — Product Requirements Document (PRD)

**Version:** 1.0 · **Date:** 2026-09-06 · **Status:** Approved for Phase 1 build

---

## 1. Vision

FoodPOS is an offline-first restaurant Point-of-Sale system for Indian F&B outlets
(dine-in, takeaway, delivery). A **Flutter front-end** (waiter tablet / cashier
desktop) talks to a **Go back-end** over REST + WebSocket. The terminal must keep
taking orders during a network outage and sync automatically on reconnect.

**North-star:** a cashier can open a shift, take a dine-in order, fire a KOT,
close the bill with GST, and reconcile the drawer — in under 90 seconds, offline-tolerant.

## 2. Users & Roles

| Role | Capabilities |
|------|-------------|
| Admin | Everything: settings, outlets, staff, voids, refunds, reports |
| Manager | Shift open/close, refunds, discounts > threshold, table ops, reports |
| Cashier | Orders, billing, payments, cash in/out, KOT |
| Waiter | Orders, KOT, table status, guest details |
| Kitchen (display only) | KOT board — accept, prepare, ready, served |

Login is PIN-based per terminal; a manager PIN gate guards privileged actions.

## 3. Functional Requirements

### 3.1 Auth & Session
- **FR-A1** Staff login by selecting a profile + 4–6 digit PIN. Session = JWT
  (short-lived) + refresh. Roles enforced server-side.
- **FR-A2** Outlet selection at start; terminal binds to one outlet per shift.
- **FR-A3** Manager-PIN re-auth for: refunds, discounts > 20% or > ₹500,
  item cancellation after KOT, settings changes.

### 3.2 Menu
- **FR-M1** Menu items with category, veg/non-veg, price, image, description,
  bestseller flag, availability toggle.
- **FR-M2** Variants (e.g. Half/Full) and modifier groups (single/multi-select,
  optional/required). Modifier prices add to line total.
- **FR-M3** Search by name/category; veg-only filter; category tabs.

### 3.3 Tables & Floor
- **FR-T1** Tables with seats, floor, status: `available | occupied | reserved |
  billing | cleaning`. Reserved/cleaning → available transitions are explicit
  provider actions.
- **FR-T2** Move table (carries the active order), merge (secondary points to
  primary, secondary's active order is re-homed), unmerge.

### 3.4 Orders & Cart
- **FR-O1** Order types: dine-in, takeaway, delivery. Auto-numbered `ORD-n`.
- **FR-O2** Line items = menu item + variant + modifiers + note; quantity ±.
  Duplicate line (same item+variant+modifiers+note) increments quantity.
- **FR-O3** Billing math (single source of truth, rounded to 2 dp):
  `subtotal → discount (clamp 0..subtotal; percent 0..100) → net → tax → charges → grandTotal`.
  GST base = net + service charge (Indian rule). Inclusive pricing supported.
- **FR-O4** Item cancellation requires a reason and is audited.

### 3.5 KOT (Kitchen Order Tickets)
- **FR-K1** "Send to kitchen" fires only un-sent, un-cancelled items; increments
  KOT counter; items flip `isKOTSent`.
- **FR-K2** KOT board shows live status: `new → preparing → ready → served`
  (+ `cancelled`). Status transitions enforced by the backend state machine.
- **FR-K3** KOT updates push to all terminals via WebSocket.

### 3.6 Payments & Receipt
- **FR-P1** Payment methods: Cash, UPI, Card (enum, not free text). Split-tender
  supported later (Phase 3).
- **FR-P2** Cash payment: `amountReceived ≥ grandTotal` enforced; change due
  computed; short-payment rejected with a clear message.
- **FR-P3** Invoice number issued at payment; receipt shows table/type, waiter,
  GST breakup (CGST/SGST), charges, discount, paid, change.
- **FR-P4** Refunds: amount validated `0 < amt ≤ paid`, mode recorded
  (Cash/UPI/Original), reason required, full refund cancels the order; cash
  refunds reduce the drawer, digital refunds do not.

### 3.7 Shifts & Cash Drawer
- **FR-S1** One open shift per outlet+terminal. Open captures opening cash +
  denominations; close captures counted cash + denominations and computes
  expected cash & variance.
- **FR-S2** `expectedCash = opening + cashSales + cashIn − expenses(cash) − cashOut − cashRefunds`.
- **FR-S3** Cash in/out require amount > 0; cash-out warns when it exceeds drawer.
- **FR-S4** Deleting a cash expense reverses the shift expense total.

### 3.8 Expenses, Customers, Inventory
- **FR-E1** Expenses with category, vendor, payment method; today/month totals.
- **FR-C1** Customers keyed by normalized phone (digits-only); visits, lifetime
  spend, last visit auto-update on payment; outstanding credit tracked.
- **FR-I1** Inventory items with stock, min-stock, unit, cost; low-stock view;
  stock adjustments are logged (who/why/when) and clamp ≥ 0.
- **FR-I2** Suppliers + purchase records with payment status enum.

### 3.9 Reports & Dashboard
- **FR-R1** All report numbers are derived from persisted data — no fabricated
  fallbacks. Sales = shift-scoped; AOV = shift sales ÷ completed orders in shift.
- **FR-R2** Order-type split and payment-mode split computed from real orders.
- **FR-R3** Shift Z-report: totals per tender, refunds, expenses, expected vs
  counted cash, variance.

### 3.10 Offline & Sync
- **FR-X1** Reads served from local cache; writes queued locally and replayed
  FIFO on reconnect (idempotency keys).
- **FR-X2** Sync status surfaced in UI; server is source of truth on conflict
  (last-write-wins with server timestamps), except: payment events never
  auto-drop — they surface for review.

## 4. Non-Functional Requirements

| NFR | Target |
|-----|--------|
| Latency | p95 local API read < 50 ms; order save < 150 ms |
| Offline | Full ordering + billing flow works with zero connectivity |
| Concurrency | 5 terminals / outlet without double-billing a table (server-side table lock via active order) |
| Money | Integer paise on the wire & in DB; display ₹ with 2 dp |
| Security | bcrypt PINs, JWT (15 min) + refresh (7 d), TLS in prod, role middleware |
| Audit | Cancelled items, refunds, discounts, stock changes, cash movements all persisted with actor + reason |
| Platforms | Windows/desktop (primary), Android tablet, Web (kitchen display) |

## 5. Out of Scope (v1)

Printer hardware integration (ESC/POS queued as Phase 4), loyalty points,
multi-currency, taxation beyond GST, kitchen video, online ordering intake.

## 6. Success Metrics

- Zero double-billed tables in a 30-outlet pilot month.
- Shift variance ≤ ±₹50 on 95% of closes.
- Offline order loss rate: 0 (queue survives app restart).
- Backend p95 < 150 ms at 50 rps/order writes.
