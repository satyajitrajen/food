# Design Brief: P5 — Security Hardening + Printer Hooks + Load Test
- PRD ref: NFR Security/Audit, P5.1–P5.3
- Status: implemented (2026-09-07)

## Contracts
- Migration 002 adds `refresh_tokens(id, staff_id, token_hash UNIQUE, expires_at, revoked_at, created_at)`
  and `client_id` columns on orders/order_items (D-008).
- Auth: login returns `{token, refresh_token, expires_at, staff}`. Refresh rotates
  (single-use, SHA-256 hashed at rest, 7d). Reuse/expiry → 401 invalid_refresh_token.
  `POST /auth/logout {refresh_token}` revokes (public + rate-limited).
- Rate limiting: fixed-window per-IP limiter (20/min) on login/refresh/logout →
  429 `rate_limited` + Retry-After.
- GET /staff public (D-007) for pre-auth profile rendering.
- Printer (Flutter): `PrinterAdapter` + `EscPosBuilder` + `buildReceiptBytes`/
  `buildKotBytes`; adapters: raw-TCP-9100 (desktop) / NullPrinter (web, unset).
  Hooks: KOT auto-print (settings.auto_print_kot) on KOT fire; receipt print on pay.
  Failures surface via `provider.printerError` (no crash, no lost order).
- Load test: `cmd/loadtest` (paced ticker, unique idempotency keys, p50/p95/p99).

## Invariants (testable)
- I1: a presented refresh token is revoked on first use; reuse → 401.
- I2: garbage/expired/revoked refresh → 401.
- I3: >20 logins/min from one IP → 429.
- I4: loadtest at 50 rps keeps p95 < 150 ms (measured 9.9 ms).

## Money
- No new money paths (counted/expected cash unchanged).

## Edge cases
- bcrypt cost review: default 10 (config-clamped 4–15) kept; login latency ~1ms at cost 10 in tests (cost 4); production default 10 stands — no change needed.
- Logout with unknown token → 401 (idempotent client-side).

## Test plan
- Integration: TestRefreshTokenRotation (rotate, reuse-detect, garbage, logout), TestRateLimit (429 after burst).
- Load: live run — 1000 flows @ 50 rps: p50 8.8ms / p95 9.9ms / p99 11.3ms; headroom run @ ~130 flows/s still 0 failures (p95 1.37s — single-writer SQLite saturation documented).

## Open questions
- TLS termination is a deployment concern (reverse proxy) — not in-process.
