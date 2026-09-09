# Decisions (append-only, newest last)

## D-001 · 2026-09-06 · Money as integer paise across API + Go services
Float money caused drift in v0 review (F-16). Flutter converts at display edge only.
Alternatives: decimal library in Dart (heavier, still leaks), strings (ambiguous math).

## D-002 · 2026-09-06 · SQLite default DB, Postgres-compatible SQL style
Pilot outlets need zero-ops; pure-Go driver (modernc.org/sqlite) keeps Windows
builds simple. Postgres swap is Phase 5 config concern.

## D-003 · 2026-09-06 · Keep PosProvider as façade during P0/P1
Splitting into domain providers mid-backend-integration doubles risk. Split lands
in P2.5 once ApiClient exists.

## D-004 · 2026-09-06 · Tender-aware refunds
Cash refunds reduce drawer; digital refunds tracked but not in expected cash
(F-14/F-shift model). Field set: refunds_cash + refunds_digital.

## D-005 · 2026-09-06 · GST base = net + service charge
Indian restaurant convention (service charge attracts GST). Documented in PRD FR-O3.

## D-006 · 2026-09-07 · Refresh tokens: opaque, hashed, rotating single-use
POST /auth/refresh now takes `{refresh_token}` (was: old access token). The
server stores only SHA-256 hashes; every refresh revokes the presented token
and issues a new pair (7-day expiry). Reuse/expiry → 401 `invalid_refresh_token`.
Alternative (refresh JWTs signed like access tokens) rejected: cannot revoke
server-side without a table anyway.

## D-007 · 2026-09-07 · GET /staff is public
PRD FR-A1: login = pick profile + PIN, so terminals must render staff profiles
pre-auth. PINs stay server-side (bcrypt); response carries no PIN material.
Rate limiter (20 req/min/IP) guards auth endpoints incl. login/refresh/logout.

## D-008 · 2026-09-07 · client_id echo for offline id remapping
Offline clients create orders/items with local ids (`client_id` on
POST /orders, POST /orders/{id}/items). Server stores + echoes it so the
Flutter sync engine can remap local→server ids (idmap) when replaying the
outbox FIFO. Alternative (server-side id aliases table) rejected: column echo
is enough and keeps the table schema clean.

## D-009 · 2026-09-07 · Flutter money convention: paise at the API edge
Dart models keep double rupees; `lib/core/api/dto.dart` converts (×100/÷100)
on every request/response. Server remains the single billing-math source of
truth; the client's optimistic math is replaced by server truth on ack/SSE.

## D-010 · 2026-09-07 · Offline writes: optimistic local + persisted outbox
PosProvider keeps its synchronous façade (D-003 upheld; no screen rewrite).
Every write applies locally then pushes through SyncEngine; network failures
persist the op (FIFO, Idempotency-Key = op id) in SharedPreferences and replay
on reconnect. 4xx rejections drop the op and surface the message (server truth).
Payment events are replayed idempotently, never dropped (PRD FR-X2).

## D-011 · 2026-09-07 · SSE (not WebSocket) for realtime; P4.3 satisfied
Backend uses SSE on GET /api/v1/ws; Flutter subscribes with a streamed http
request (works on all platforms incl. web kitchen display). Events: kot.*,
table.updated, order.updated, shift.updated → applied as server truth.

## D-012 · 2026-09-07 · Printing = ESC/POS byte builder + pluggable adapter
`PrinterAdapter` interface (TCP raw-9100 on desktop, no-op on web/unset).
Receipts/KOTs render to bytes via EscPosBuilder; KOT auto-print follows
settings.auto_print_kot. Hardware-bringing adapters slot in later (Q-4).

## D-013 · 2026-09-07 · Purchases post stock intake through the adjustment log
POST /purchases increments inventory stock per line and writes
stock_adjustments rows (reason "Purchase <invoice>") inside one txn — same
audit trail as manual adjustments. `pending` purchases raise supplier
outstanding; PATCH pending→paid settles it (never negative).

## D-014 - 2026-09-07 - Inclusive GST: tax extracted, flag rides the order
Migration 003 adds orders.is_tax_inclusive; order create inherits it from the
outlet settings (with the settings GST percent, D-005 charges unchanged).
ApplyBilling extracts tax = base·pct/(100+pct) and the grand total stays at
menu price + charges (no tax added). Dart mirrors this in order_model so
offline bills match (single source of truth stays the Go service).

## D-015 - 2026-09-07 - Manager PIN gates enforced server-side (FR-A3)
Refunds (always), item cancellation after KOT (incl. qty→0 removals) and
discounts above 20%/₹500 require manager_pin in the request; the server
verifies it against active manager/admin bcrypt PINs and answers
403 manager_pin_required / invalid_manager_pin. The Flutter manager dialog
returns the PIN (previously bool) and threads it into the ops payloads so
offline replays carry authorization too.

## D-016 - 2026-09-07 - PATCH /menu/{id} is a true partial patch
MenuItemUpsert fields became pointers; PATCH only writes provided fields and
only rebuilds variants/modifier groups when explicitly supplied (a partial
body used to wipe name/category_id → FK failure). POST still requires
name + category_id. Frontend menu.update ops send full bodies (compatible).

## D-017 - 2026-09-07 - Offline PIN fallback = salted-hash PinVault, not plaintext
On every SERVER-verified PIN (login, manager gate) the terminal caches
sha256("foodpos:<staffId>:<salt>:<pin>") with a per-staff random salt in
SharedPreferences (PinVault). Offline login and offline manager gates verify
against these hashes only; plaintext demo PINs remain solely in demo mode
(apiEnabled=false). Trade-off (visible, not silent): a terminal can only
offline-authenticate staff who logged in on it at least once.

## D-018 - 2026-09-07 - SSE connect via single-use tickets, not the raw JWT
EventSource cannot set headers, so the JWT in the query would land in proxy
logs. POST /api/v1/ws/ticket (authenticated) issues a one-time ticket
(SHA-256 at rest, in-memory, 60 s TTL) carrying the caller's claims; GET /ws
consumes it and rejects reuse. The legacy 	oken= JWT param still works for
compatibility. Flutter RealtimeChannel requests a ticket before connecting.
