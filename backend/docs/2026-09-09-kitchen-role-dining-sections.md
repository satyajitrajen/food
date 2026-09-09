# Kitchen display role + dining sections + order phone — 2026-09-09

Feature release for the FoodPOS backend. Companion Flutter changes live in the
app workspace (`lib/…`); this branch contains the **backend** contract they
depend on.

## What changed

### 1. New `kitchen` role (display-only)
- **Migration** `internal/db/migrations/005_kitchen_role_sections.sql`
  - extends the `staff.role` CHECK constraint to include `'kitchen'`
  - adds `settings.sections TEXT NOT NULL DEFAULT '[]'` (JSON list of dining
    sections such as `["Garden","AC Dining","Bar"]`)
- `internal/auth/auth.go` — `RoleRank("kitchen") = 0` so it passes **no**
  `RequireRole` gate (all manager-gated writes stay blocked).
- `internal/middleware/middleware.go` — new **`DenyRoles(...)`** middleware
  (403 when the claim's role is in the deny list).
- `internal/api/server.go` — the authed `/api/v1` group is split so kitchen
  may reach only what a KDS terminal needs:
  - **Allowed:** `POST /ws/ticket`, `GET /tables|menu|orders|kots|shifts|
    expenses|customers|inventory|suppliers|purchases|settings` (terminal
    hydration) and `PATCH /kots/{id}` (the KOT state machine:
    new → preparing → ready → served).
  - **Denied to kitchen:** every write + back-office endpoint (orders create/
    pay/refund/items, tables writes, shifts, expenses, customers, inventory,
    suppliers/purchases, settings PUT, `verify-manager-pin`), plus the
    revenue dashboard and Z-report reads.
- Seed (`cmd/server/main.go`) adds a demo kitchen profile **Chef Sharma, PIN
  `5555`** (only when `FOODPOS_SEED=1`).

### 2. Overall revenue dashboard is Admin-only
- `GET /reports/dashboard` now requires `RequireRole("admin")`.
- The shift **Z-report** (`GET /reports/shift/{id}/zreport`) stays available to
  manager/cashier — close-shift reconciliation is operational, not analytics.
- The Flutter client only fetches the dashboard when the signed-in role is
  admin, so other roles never trip a 403 during hydration.

### 3. Dining sections on tables + settings
- `Table` gains a `Floor` field on `PATCH /tables/{id}` (`{"floor": "Bar"}`) so
  tables can be moved between sections (rename/re-home flows).
- `Settings` gains `sections []string` (JSON list) — GET returns it, PUT
  persists it. An empty list means "sections derive from the table floors in
  use", keeping older databases fully compatible.
- Seed inserts the default section list for demo data.

### 4. Guest phone persists on orders
- `PATCH /orders/{id}` accepts `customer_phone` (was missing, though
  `order.create` already carried it) so a phone captured at the table is
  stored server-side and available for WhatsApp bill delivery.

## Roles at a glance (server-enforced)

| Capability | admin | manager | cashier | waiter | kitchen |
|---|---|---|---|---|---|
| Revenue dashboard (`/reports/dashboard`) | ✔ | – | – | – | – |
| Everything else operational (orders, pay, KOT, shifts, expenses…) | ✔ | ✔ | ✔ | ✔ | – |
| Staff / menu / settings / inventory-create writes | ✔ | ✔ | – | – | – |
| KOT board reads + status transitions | ✔ | ✔ | ✔ | ✔ | ✔ |
| SSE ticket (`/ws`) | ✔ | ✔ | ✔ | ✔ | ✔ |
| All money & back-office writes | ✔ | ✔ | ✔ | ✔ | – |

Notes: waiter rank is unchanged (billing per product spec is waiter-visible);
kitchen is the only role that is *denied* money/back-office writes even though
it can authenticate.

## Runbook

1. Deploy the new binary; migrations in
   `internal/db/migrations/*.sql` apply automatically on startup in filename
   order (`005_kitchen_role_sections.sql` included).
2. If the database is **not** re-seeded, create the kitchen account once via
   `POST /staff` (manager/admin) with `"role": "kitchen"`.
3. Optional: `PUT /settings` with a `sections` list to name the dining areas
   (e.g. `["Garden","AC Dining","Bar"]`); move tables between them with
   `PATCH /tables/{id}` `{"floor": …}`.

## Tests

- `internal/service/service_test.go` — unit (billing/KOT/payment) — runs
  without a database.
- `internal/api/integration_test.go` + `kitchen_role_integration_test.go` —
  end-to-end over the real HTTP stack (requires PostgreSQL; set
  `FOODPOS_TEST_DSN`, default `postgres://foodpos:foodpos@localhost/foodpos_test`).
  New coverage:
  - kitchen login works, can read the KOT board and drive status, and every
    money/back-office write returns **403**
  - `/reports/dashboard` is **403** for cashier/manager/kitchen and **200** for
    admin
  - settings `sections` round-trip (order + values preserved)
  - `PATCH /orders/{id}` `customer_phone` persists

```powershell
# unit-only (no DB needed)
go vet ./... ; go build ./... ; go test ./internal/service ./internal/auth ./internal/middleware ./internal/store ./internal/models

# full suite (needs Postgres)
$env:FOODPOS_TEST_DSN = 'postgres://foodpos:foodpos@localhost/foodpos_test?sslmode=disable'
go test ./internal/api
```
