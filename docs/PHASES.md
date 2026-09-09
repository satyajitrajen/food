# FoodPOS — Phased Development Plan

**Version:** 1.0 · **Date:** 2026-09-06
Companion docs: `docs/PRD.md` · `docs/ARCHITECTURE.md` · `docs/AGENTS.md`

Each phase = design briefs first (Design Agent), then build + verify gates.
Phase exit requires: tests green, `PROJECT_STATE.md` updated, phase report written.

---

## Phase 0 — Stabilize v0 (Flutter-only) ✅ *in this drop*
Goal: fix every HIGH/MED defect found in the full-codebase review so the
existing demo is trustworthy before backend work.

- P0.1 Model correctness: `unitPrice` honors `isSelected`; add `copy()` to
  `MenuItem`/`ProductVariant`/`RestaurantOrder`; KOT qty ignores cancelled;
  round money getters.
- P0.2 Provider hardening: no `firstWhere` without `orElse`; payment inserts
  into orders; refund/discount/charge/cash validation; delete-reverses-cash-
  expense; refund by tender; manager-PIN login by staff id.
- P0.3 Screen fixes: menu minus-button crash; refund parse fallback;
  discount cap; underpayment guard; single-select modifier toggle + required
  groups; completed-order footer guard; reserved/cleaning via provider;
  split-bill remainder; report uses real data; close-shift denominations seed.
- P0.4 `flutter analyze` clean, tests green.

## Phase 1 — Backend Foundation (Go)
- P1.1 Scaffold `backend/` (chi, config, logging, request-id, error envelope).
- P1.2 DB layer: SQLite (pure-Go driver) + embedded migrations + seed.
- P1.3 Auth: PIN login → JWT + refresh; role middleware; manager-pin verify.
- P1.4 Domain read/write APIs: outlets, staff, tables, menu (with variants/
  modifiers), settings.
- P1.5 Verify: `go vet && go test && go build`; httptest integration suite.

## Phase 2 — Order Lifecycle (the heart)
- P2.1 Orders + items + modifiers (idempotent create; table-occupancy guard).
- P2.2 Order math service in Go (paise ints): discount clamp, GST on
  net+service, charges, rounding — mirrors PRD FR-O3.
- P2.3 KOT FSM + fire-unsent-items; WebSocket broadcast (`kot.*`, `table.*`).
- P2.4 Payments: pay endpoint (cash overpay/change, split-tender v1),
  invoice numbering, refunds with validation + tender-aware drawer math.
- P2.5 Flutter `ApiClient` + swap `PosProvider` writes to API (offline shim).

## Phase 3 — Shifts, Money & Inventory
- P3.1 Shift open/close with denominations, expected-cash formula, Z-report.
- P3.2 Cash in/out with drawer-balance checks; expense create/delete reversal.
- P3.3 Customers (phone-normalized), auto spend/visit rollups.
- P3.4 Inventory + stock adjustment log; suppliers/purchases.
- P3.5 Reports endpoints (dashboard, sales, Z-report) — zero fabricated data.

## Phase 4 — Offline & Sync
- P4.1 Flutter outbox (idempotency keys, FIFO replay, restart-safe).
- P4.2 Cache-first reads; sync status UI; server-truth conflict policy.
- P4.3 Kitchen display on web via WS.

## Phase 5 — Hardening & Release
- P5.1 Printer hooks (ESC/POS adapter interface), KOT auto-print setting.
- P5.2 Load test (50 rps writes), soak, security pass (JWT rotation, rate
  limits, bcrypt cost review).
- P5.3 Release checklist + versioned migrations + backup/restore runbook.

---

### Dependency graph
```
P0 ──▶ P1 ──▶ P2 ──▶ P3 ──▶ P4 ──▶ P5
              ▲      ▲
              └── WS events (P2.3) feed P4.3
```
