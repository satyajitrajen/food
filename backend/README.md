# FoodPOS Backend — Go API server

REST + SSE backend for the FoodPOS Flutter app. PostgreSQL with
integer-paise money math throughout. See `../docs/ARCHITECTURE.md` for the
full design and `../docs/PRD.md` for requirements.

## Single binary (site + APIs)

The built React landing & owner/superadmin console is embedded and served at
`/` and `/console/*`; APIs stay under `/api/v1`, media under `/media/*`.
Refresh the embedded site with `make web` (builds `../landing`) before
`go build ./cmd/server` — the assets are gitignored (`internal/web/webroot/`).

## Run (local development)

```powershell
cd backend
$env:FOODPOS_DSN = 'postgres://foodpos:foodpos@localhost/foodpos?sslmode=disable'
$env:FOODPOS_DEV = '1'       # dev mode: built-in JWT secret, reset tokens echoed
go run ./cmd/seed            # optional demo dataset (idempotent, dev only)
go run ./cmd/server          # :8080 (FOODPOS_PORT)
```

The server never seeds tenant data itself: on boot it only migrates and
upserts the plan catalog. Outside dev mode it refuses to start without a
real `FOODPOS_JWT_SECRET` (≥ 16 chars).

### Demo data (`cmd/seed`)

`go run ./cmd/seed` loads the demo organization **org-01** (org code
`HISHOBKR`) with outlets `out-01` (Baner) and `out-02` (Kothrud), staff,
12 tables per outlet, a sample menu with variants/add-ons, inventory and
suppliers, plus an active subscription. It upserts, so it is safe to re-run,
and it **refuses to run when `FOODPOS_ENV=production`**.

Demo PINs: admin `0000`, manager `9999`, cashier `1234`, waiter `1111`,
kitchen `5555` (Kothrud: manager `8888`, cashier `3333`, waiter `2222`,
kitchen `6666`). See
[`docs/2026-09-09-kitchen-role-dining-sections.md`](docs/2026-09-09-kitchen-role-dining-sections.md)
for the kitchen role, dining sections, and role/permission matrix,
[`docs/2026-09-09-menu-photos-addons.md`](docs/2026-09-09-menu-photos-addons.md)
for menu photo upload and editable variants/add-ons, and
[`docs/2026-09-09-saas-conversion.md`](docs/2026-09-09-saas-conversion.md)
for the SaaS tenant/subscription model, superadmin setup and the manual
billing runbook.

### Operator CLI (`cmd/admin`)

Runs directly against `FOODPOS_DSN` (migrates first). Flags accept `-x` or
`--x`.

| Command | Purpose |
|---------|---------|
| `list [status]`, `show <org>`, `stats` | Inspect organizations |
| `activate <org> [-days 30] [-method bank] [-amount <paise>] [-ref] [-note]` | Manual payment → active + invoice |
| `extend <org> -days N`, `suspend <org>`, `cancel <org>` | Subscription admin |
| `create-org -name -email -owner -password -outlet -pin [-terminal] [-gstin] [-plan pro]` | New tenant: org + owner login + first outlet + protected POS admin (prints the org code) |
| `import-menu -outlet <id> -csv <file> [-replace]` | Upsert a menu CSV into an outlet |
| `move-outlet -outlet <id> -to-org <org>` | Move an outlet (and its outlet-bound staff, attendance, push tokens) to another org; revokes its sessions |

**Menu CSV format** (same as `../assets/green_candle_menu.csv`): UTF-8 (BOM
ok), header
`Category,Item (Marathi),Item English Transliteration,Half Price (₹),Full Price (₹),Variants,Bestseller,Veg,Description`.
The English transliteration is the item name (the Marathi name is prefixed to
the description); prices are rupees. With a Half price the item gets
variants Half/Full and its base price is Full. Items are matched by
outlet + case-insensitive name, so re-imports update in place (ids and order
history are kept, soft-deleted matches are revived). `-replace`
soft-deletes live items missing from the file. Category order follows the
file. A malformed row aborts the whole import before anything is written
(parser: `internal/menuimport`).

### Runbook: move Green Candle out of the demo org (production)

Earlier builds seeded Green Candle (`out-green-candle`,
`out-green-candle-balawadi`) into the demo org `org-01` when
`FOODPOS_SEED=1`. To give the restaurant its own tenant. **Do this by hand
with a backup; nothing runs automatically.**

1. **Back up**: `pg_dump "$FOODPOS_DSN" -Fc -f pre-gc-move.dump`.
2. **Deploy** this build with `FOODPOS_JWT_SECRET` set and `FOODPOS_DEV` /
   `FOODPOS_SEED` unset (the seed variable no longer does anything).
3. **Inspect** what belongs to the outlets:
   ```sql
   SELECT id, name, org_id FROM outlets WHERE id LIKE 'out-green-candle%';
   SELECT id, name, role, outlet_id FROM staff
    WHERE org_id = 'org-01' AND (outlet_id LIKE 'out-green-candle%' OR outlet_id IS NULL);
   ```
   Org-wide staff (`outlet_id IS NULL`) do **not** move. Bind the Green
   Candle people to an outlet first, e.g.
   `UPDATE staff SET outlet_id = 'out-green-candle' WHERE id IN ('…');`
   (or recreate them in the new org afterwards).
4. **Create the tenant** (creates one extra, empty setup outlet — rename or
   leave it; it counts toward the plan's outlet limit):
   ```sh
   go run ./cmd/admin create-org -name "Hotel Green Candle" -email owner@… \
     -owner "…" -password '…' -outlet "Green Candle (setup)" -pin ……
   ```
   Note the printed org id and **org code**.
5. **Move the outlets**:
   ```sh
   go run ./cmd/admin move-outlet -outlet out-green-candle -to-org <new_org>
   go run ./cmd/admin move-outlet -outlet out-green-candle-balawadi -to-org <new_org>
   ```
   Orders, KOTs, shifts, menu and settings are outlet-scoped and follow
   automatically.
6. **Bill it**: `go run ./cmd/admin activate <new_org> -days 365 -method bank -amount <paise> -ref <utr>`.
7. **Re-login terminals** with the new org code (their sessions were
   revoked). Optionally refresh the menu:
   `go run ./cmd/admin import-menu -outlet out-green-candle -csv ../assets/green_candle_menu.csv`.
8. If `org-01` is only demo data, `go run ./cmd/admin suspend org-01`.

## Config (env)

| Var | Default | Purpose |
|-----|---------|---------|
| `FOODPOS_PORT` | 8080 | HTTP listen port |
| `FOODPOS_DSN` | — | PostgreSQL connection string |
| `FOODPOS_JWT_SECRET` | — (required) | JWT signing secret; only `FOODPOS_DEV=1` falls back to a dev secret |
| `FOODPOS_DEV` | 0 | `1` = dev conveniences (ignored when `FOODPOS_ENV=production`) |
| `FOODPOS_ENV` | development | `production` disables dev mode and `cmd/seed` |
| `FOODPOS_CORS_ORIGINS` | (empty = CORS off) | comma-separated origins, or `*` |
| `FOODPOS_FCM_CREDENTIALS` | (empty = push off) | path to a Firebase service-account JSON (FCM HTTP v1) |
| `FOODPOS_BCRYPT_COST` | 10 | PIN hashing cost |
| `FOODPOS_UPLOAD_DIR` | ./uploads | Menu photo storage (served at `/media/*`) |

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
- `internal/api/kitchen_role_integration_test.go` — kitchen display-only
  gates, admin-only revenue dashboard, settings sections round-trip, order
  customer-phone patch.
- `internal/api/menu_admin_integration_test.go` — menu create/edit with
  variants & add-on groups, availability toggle preserving add-ons, photo
  upload + public media serving, cashier upload denied.
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
GET  /outlets?org_code= (public)              GET /outlets/{id}   PATCH /outlets/{id} (manager)
GET  /staff?org_code=&outlet_id= (public: id/name/role/avatar only)   POST /staff (manager)
GET  /tables?outlet_id=&floor=                  POST /tables
PATCH /tables/{id} {status,guest_count,waiter_id,floor}   POST /tables/{id}/move|merge|unmerge
GET  /menu?outlet_id=&category_id=              GET/POST/PATCH/DELETE /menu*
POST /uploads/menu-image (manager; multipart)   GET /media/* (public photos)
GET  /orders?status=a,b&from=&to=&before=&limit=1..500   POST /orders
GET/PATCH /orders/{id}                         POST /orders/{id}/items
PATCH /orders/{id}/items/{itemId} {quantity}   (0 cancels the line)
POST /orders/{id}/items/{itemId}/cancel {reason}
POST /orders/{id}/kot                          GET /kots?status=
PATCH /kots/{id} {status}                      (FSM: new→preparing→ready→served)
POST /orders/{id}/pay {method:cash|upi|card|credit,amount_received_paise,splits[],reference,customer_id}
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
GET  /settings          PUT /settings (manager; incl. sections JSON list)
GET  /reports/dashboard?from=&to= (admin; default today in outlet tz)   GET /reports/shift/{id}/zreport
POST /ws/ticket → GET /ws?ticket=   (single-use ticket; SSE: kot.*, table.*, order.*, shift.*, outlet.*)
```

Offline-first clients may pass `client_id` on order/item creates; the server
echoes it so clients can remap local→server ids after outbox replays.

## Layout

```
cmd/server          entrypoint (migrate + plan catalog + serve)
cmd/seed            dev-only demo dataset
cmd/admin           operator CLI (billing, create-org, import-menu, move-outlet)
internal/menuimport menu CSV parser
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
