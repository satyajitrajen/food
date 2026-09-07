# FoodPOS Backend — Go API server

REST + SSE backend for the FoodPOS Flutter app. SQLite (default) with
integer-paise money math throughout. See `../docs/ARCHITECTURE.md` for the
full design and `../docs/PRD.md` for requirements.

## Run

```powershell
cd backend
$env:FOODPOS_SEED = '1'      # load demo outlets/staff/menu/tables
$env:FOODPOS_PORT = '8080'   # default
$env:FOODPOS_DB   = 'foodpos.db'
go run ./cmd/server
```

Demo staff PINs after seeding: cashier `1234`, manager `9999`, admin `0000`.

## Config (env)

| Var | Default | Purpose |
|-----|---------|---------|
| `FOODPOS_PORT` | 8080 | HTTP listen port |
| `FOODPOS_DB` | foodpos.db | SQLite file path |
| `FOODPOS_JWT_SECRET` | dev-secret-change-me | JWT signing secret (change in prod!) |
| `FOODPOS_SEED` | 0 | `1` seeds demo data |
| `FOODPOS_BCRYPT_COST` | 10 | PIN hashing cost |

## Verify

```powershell
go vet ./... ; go test ./... ; go build ./...
```

- `internal/service/service_test.go` — billing math, KOT state machine,
  payment/refund validation (unit).
- `internal/api/integration_test.go` — full lifecycle over real HTTP:
  login → order → table-occupancy guard → items+modifiers → KOT FSM →
  payment → refund → shift close → Z-report, plus idempotency, role gates,
  purchases/stock intake, customer credit, refresh-token rotation and the
  login rate limiter.
- `cmd/loadtest` — paced order-write load test (create → item → KOT → pay)
  with p50/p95/p99 latencies:

```powershell
go run ./cmd/loadtest -base http://localhost:8080 -rps 50 -duration 20s
```

## API quick reference

Base `/api/v1`, auth `Authorization: Bearer <jwt>`, writes accept
`Idempotency-Key`. Errors: `{ "error": { "code", "message", "request_id" } }`.
Access tokens live 15 min; refresh tokens (opaque, hashed at rest, single-use
rotating) live 7 days.

```
POST /auth/login {staff_id,pin,outlet_id}  → {token,refresh_token,...}
POST /auth/refresh {refresh_token}         → rotated pair (old revoked)
POST /auth/logout {refresh_token}          POST /auth/verify-manager-pin {pin}
GET  /outlets                                  GET /outlets/{id}
GET  /staff (public: login profiles)   POST /staff (manager)
GET  /tables?outlet_id=&floor=                  POST /tables
PATCH /tables/{id}     POST /tables/{id}/move|merge|unmerge
GET  /menu?outlet_id=&category_id=              GET/POST/PATCH/DELETE /menu*
GET  /orders?outlet_id=&status=                 POST /orders
GET/PATCH /orders/{id}                         POST /orders/{id}/items
PATCH /orders/{id}/items/{itemId} {quantity}   (0 cancels the line)
POST /orders/{id}/items/{itemId}/cancel {reason}
POST /orders/{id}/kot                          GET /kots?status=
PATCH /kots/{id} {status}                      (FSM: new→preparing→ready→served)
POST /orders/{id}/pay {method,amount_received_paise,splits[]}
POST /orders/{id}/refund {amount_paise,reason,mode}
GET  /shifts/current   POST /shifts/open       POST /shifts/current/close
POST /shifts/current/cash-move {type,amount_paise,reason}
GET/POST /expenses   DELETE /expenses/{id}     GET /customers?q=  POST /customers
POST /customers/{id}/credit {kind:sale|settlement,amount_paise,reason}
GET  /customers/{id}/credit-log
GET  /inventory[?low=1] POST /inventory        POST /inventory/{id}/adjust
GET  /inventory/{id}/adjustments                (stock audit log)
GET  /suppliers         POST /suppliers
GET  /purchases         POST /purchases {invoice_no,supplier_id,status,total_paise,items[]}
PATCH /purchases/{id} {status}   (pending→paid settles supplier outstanding)
GET  /settings          PUT /settings (manager)
GET  /reports/dashboard GET /reports/shift/{id}/zreport
GET  /ws?outlet_id=&token=   (server-sent events: kot.*, table.*, order.*, shift.*)
```

Offline-first clients may pass `client_id` on order/item creates; the server
echoes it so clients can remap local→server ids after outbox replays.

## Layout

```
cmd/server          entrypoint + demo seed
internal/config     env config
internal/db         open + embedded SQL migrations
internal/models     wire structs (money = int64 paise)
internal/store      SQL repositories (no business rules)
internal/service    billing math, KOT FSM, payment/refund validation
internal/api        chi routes + handlers
internal/middleware JWT auth, roles, request-id, recover
internal/ws         outlet-scoped SSE event hub
internal/httpx      JSON helpers + error envelope
internal/auth       bcrypt PINs + JWT
```
