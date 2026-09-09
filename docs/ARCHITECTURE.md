# FoodPOS — System Architecture

**Version:** 1.0 · **Date:** 2026-09-06

---

## 1. System Overview

```
┌───────────────────────────────┐         ┌──────────────────────────────────┐
│  Flutter Clients              │         │  Go Backend (foodpos-server)     │
│  ┌─────────┐ ┌─────────┐      │  HTTPS  │  ┌────────────┐                  │
│  │ Cashier │ │ Waiter  │──────┼──REST──▶│  │ chi Router │                  │
│  └─────────┘ └─────────┘      │  WSS    │  └─────┬──────┘                  │
│  ┌───────────────────────┐    │         │  ┌─────▼──────┐  ┌───────────┐  │
│  │ Kitchen Display (web) │────┼──WSS───▶│  │ Handlers   │─▶│ Services  │  │
│  └───────────────────────┘    │         │  └────────────┘  └────┬──────┘  │
│                               │         │  ┌────────────┐  ┌────▼──────┐  │
│  Local cache: sqflite/        │         │  │ Middleware │  │Repository │  │
│  hive + write-ahead outbox    │         │  │ auth,role, │  └────┬──────┘  │
│  └── Outbox queue ────────────┼─replay─▶│  │ req-id,log │  ┌────▼──────┐  │
└───────────────────────────────┘         │  └────────────┘  │  SQLite / │  │
                                          │  ┌────────────┐  │  Postgres │  │
                                          │  │ WS Hub     │  └───────────┘  │
                                          │  │ (KOT events│                 │
                                          │  │  + sync)   │                 │
                                          └──└────────────┘─────────────────┘
```

- **Front-end (existing):** Flutter, `provider` state management, 60+ screens.
- **Back-end (new):** Go 1.27, `chi` router, `pgx`-style repository layer over
  SQLite (default, zero-ops for pilot) or Postgres (prod, via build tag/config).
- **Realtime:** one WebSocket hub per outlet; KOT + table + sync events broadcast.

## 2. Go Backend — Layered Design

```
backend/
├── cmd/server/main.go            # wiring: config → db → repos → services → routes
├── internal/
│   ├── config/config.go          # env config (PORT, DB, JWT_SECRET, SEED)
│   ├── db/db.go                  # sql.DB + pragmas + migrate(embedded SQL)
│   ├── db/migrations/            # 001_init.sql ... (embedded, ordered)
│   ├── models/                   # plain structs + JSON tags (match Flutter models)
│   ├── repository/               # one repo per aggregate, SQL only, no business logic
│   ├── service/                  # business rules: order math, KOT FSM, shift math
│   ├── httpx/                    # shared helpers: JSON encode/decode, errors, req-id
│   ├── middleware/               # JWT auth, role gate, request-id, recover, logging
│   └── ws/hub.go                 # outlet-scoped pub/sub broadcast
├── api/openapi.yaml              # (Phase 3) contract for Flutter codegen
└── Makefile
```

### 2.1 Layer rules
- **repository**: SQL + scanning only. Returns `sql.ErrNoRows` → mapped to `ErrNotFound`.
- **service**: owns invariants. All money as `int64` paise. Validates state machines.
- **handler**: transport only — decode, call service, encode, map errors to HTTP.
- No layer may import a layer above it.

### 2.2 Money rule
All monetary values cross the API as **decimal strings or integer paise**
(`"grand_total_paise": 26460`). The Flutter layer converts for display.
This kills the float drift class of bugs found in review.

### 2.3 Key state machines (enforced in service layer)

```
Order:   received → preparing → ready → served → billing → completed
                 ↘ cancelled (audit reason)          ↘ cancelled (full refund)
KOT:     new → preparing → ready → served            (cancelled allowed pre-served)
Table:   available → occupied → billing → available ; reserved/cleaning → available
Shift:   (none) → open → closed                      (one open per outlet+terminal)
```

### 2.4 Concurrency: table double-billing guard
`POST /orders` with `table_id` inside a transaction:
1. `SELECT ... FROM tables WHERE id=? FOR UPDATE` (SQLite: immediate txn)
2. If `active_order_id IS NOT NULL` → `409 table_occupied`.
3. Insert order, update table. Commit.

### 2.5 Idempotency & offline replay
- Clients send `Idempotency-Key` header on writes (order create, payment, KOT).
- Server stores key → response in `idempotency_keys` table (24 h TTL).
- Replay returns the stored response → safe outbox re-send.

## 3. Data Model (core tables)

```
outlets(id, name, address, terminal, gstin, fssai, phone, is_online)
staff(id, outlet_id?, name, role, pin_hash, avatar_url, mobile, is_active)
tables(id, outlet_id, table_number, seats, floor, status, active_order_id,
       guest_count, assigned_waiter_id, merged_with_table_id, running_minutes)
menu_categories(id, outlet_id, name, sort)
menu_items(id, outlet_id, category_id, name, description, price_paise, is_veg,
           image_url, is_bestseller, is_available, sort)
product_variants(id, menu_item_id, name, price_paise)
modifier_groups(id, menu_item_id, name, is_multi_select, is_required, sort)
modifier_items(id, group_id, name, price_paise, sort)
orders(id, outlet_id, order_number, type, status, table_id, customer_name,
       customer_phone, guest_count, waiter_id, subtotal_paise, discount_percent,
       discount_paise, discount_reason, tax_percent, tax_paise, service_paise,
       packaging_paise, delivery_paise, grand_total_paise, invoice_number,
       paid_at, payment_method, paid_paise, change_paise, order_note, idempotency_key,
       created_at, updated_at)
order_items(id, order_id, menu_item_id, variant_id, quantity, unit_paise,
            total_paise, note, is_kot_sent, is_cancelled, cancel_reason)
order_item_modifiers(order_item_id, modifier_item_id, name, price_paise)
kots(id, outlet_id, kot_number, order_id, status, waiter_id, table_number,
     order_type, note, created_at)
kot_items(kot_id, order_item_id, name, quantity)
shifts(id, outlet_id, staff_id, started_at, closed_at, opening_paise,
       opening_notes, cash_sales_paise, upi_sales_paise, card_sales_paise,
       refunds_paise, expenses_paise, cash_in_paise, cash_out_paise,
       counted_paise, closing_notes, status)
shift_denominations(shift_id, kind('open'|'close'), d500, d200, d100, d50, d20, d10)
cash_transactions(id, shift_id, type, amount_paise, reason, reference, staff_id, ts)
expenses(id, outlet_id, title, category, amount_paise, method, vendor, reference,
         note, ts, created_by)
customers(id, outlet_id, name, phone_norm UNIQUE, email, address, gstin, notes,
          visits, lifetime_spend_paise, outstanding_paise, last_visit)
inventory_items(id, outlet_id, name, unit, stock, min_stock, cost_paise)
stock_adjustments(id, item_id, delta, reason, staff_id, ts)
suppliers(id, outlet_id, name, mobile, category, outstanding_paise)
purchases(id, outlet_id, invoice_no, supplier_id, ts, total_paise, status, summary)
settings(id = outlet_id, gst_percent, is_gst_inclusive, service_percent,
         packaging_paise, delivery_paise, auto_print_kot, ...)
audit_log(id, ts, staff_id, action, entity, entity_id, meta_json)
idempotency_keys(key PK, response_code, response_body, created_at)
```

## 4. API Surface (v1)

Base: `/api/v1` · Auth: `Authorization: Bearer <jwt>` · All writes: `Idempotency-Key`

| Area | Endpoints |
|------|-----------|
| Auth | `POST /auth/login` (staff_id+pin+outlet_id→tokens), `POST /auth/refresh` (rotating), `POST /auth/logout`, `POST /auth/verify-manager-pin` |
| Outlets | `GET /outlets`, `GET /outlets/{id}` |
| Staff | `GET /staff`, `POST /staff` (manager; PIN 4-6 digits) |
| Tables | `GET /tables?floor=`, `POST /tables`, `PATCH /tables/{id}` (status, waiter, guests), `POST /tables/{id}/move`, `POST /tables/{id}/merge`, `POST /tables/{id}/unmerge` |
| Menu | `GET /menu?category_id=`, `GET /menu/{id}`, `POST /menu` (manager), `PATCH /menu/{id}` (manager), `DELETE /menu/{id}` (manager) |
| Orders | `GET /orders?status=&limit=`, `POST /orders`, `GET /orders/{id}`, `PATCH /orders/{id}` (status/note/guests/customer/charges/discount), `POST /orders/{id}/items`, `PATCH /orders/{id}/items/{itemId}`, `POST /orders/{id}/items/{itemId}/cancel` |
| Payments | `POST /orders/{id}/pay` (method cash\|upi\|card, amount_received_paise, splits[]), `POST /orders/{id}/refund` (amount_paise, reason, is_full_refund, mode) |
| KOT | `POST /orders/{id}/kot`, `GET /kots?status=`, `PATCH /kots/{id}` (status FSM: new→preparing→ready→served, cancel before served) |
| Shifts | `GET /shifts/current`, `GET /shifts`, `POST /shifts/open`, `POST /shifts/current/close`, `POST /shifts/current/cash-move` (cash_in\|cash_out) |
| Expenses | `GET /expenses?range=today\|month`, `POST /expenses`, `DELETE /expenses/{id}` |
| Customers | `GET /customers?q=`, `POST /customers`, `POST /customers/{id}/credit` (kind sale\|settlement), `GET /customers/{id}/credit-log` |
| Inventory | `GET /inventory?low=1`, `POST /inventory` (manager), `POST /inventory/{id}/adjust`, `GET /inventory/{id}/adjustments`, `GET /inventory/adjustments`; suppliers `GET/POST /suppliers`; purchases `GET/POST /purchases`, `PATCH /purchases/{id}` |
| Settings & Reports | `GET /settings`, `PUT /settings` (manager), `GET /reports/dashboard`, `GET /reports/shift/{id}/zreport` |
| Realtime | `POST /ws/ticket` (authed → single-use 60 s connect ticket, preferred), `GET /ws?outlet_id=&ticket=` — SSE events: `kot.created`, `kot.updated`, `table.updated`, `order.updated`, `shift.updated` |

Error shape (uniform):
```json
{ "error": { "code": "table_occupied", "message": "Table T04 already has order ORD-1049", "request_id": "..." } }
```

## 5. Front-end Integration (Flutter)

- `lib/services/api_client.dart` — thin HTTP client (dio/http), token refresh, base URL from settings.
- `lib/services/outbox.dart` — offline write queue (hive/sqflite) with idempotency keys.
- `lib/services/sync_service.dart` — connectivity watch, replay, cache refresh.
- `PosProvider` split into domain providers over time; Phase 1 keeps `PosProvider`
  as a façade that reads/writes through the repository service (local-first).

## 6. Cross-cutting

- **Request-id middleware** echoes `X-Request-Id` and tags logs.
- **Structured logging** (`log/slog`) with outlet/terminal/staff context.
- **Config**: env vars (`FOODPOS_PORT`, `FOODPOS_DB`, `FOODPOS_JWT_SECRET`,
  `FOODPOS_SEED=1` to seed demo data).
- **Testing**: service-layer unit tests (order math, KOT FSM, shift math),
  httptest integration tests per domain, one end-to-end happy path.
