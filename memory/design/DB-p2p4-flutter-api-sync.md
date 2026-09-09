# Design Brief: P2/P4 — Flutter ApiClient, Outbox Sync, Realtime, Cache-First Reads
- PRD ref: FR-X1, FR-X2, FR-K3, P2.5, P4.1–P4.3
- Status: implemented (2026-09-07)

## Contracts
- New Dart modules:
  - `core/api/api_client.dart` — http client: bearer auth, 401→refresh→retry, error envelope → `ApiException`, unreachable → `NetworkException` (8s timeout; health probe 1.5s).
  - `core/api/dto.dart` — the ONLY place money converts (D-009). Mappers for menu/table/order/item/KOT/shift/expense/customer/inventory/supplier/purchase/settings.
  - `core/sync/outbox.dart` — `OutboxOp{id, type, payload}` persisted FIFO in SharedPreferences; `id` = Idempotency-Key.
  - `core/sync/sync_engine.dart` — op registry, optimistic push, offline enqueue, FIFO replay, local→server idmap (D-008), ack→server-truth apply.
  - `core/sync/realtime.dart` — SSE client for GET /api/v1/ws; events applied as server truth (D-011).
- PosProvider: keeps synchronous façade (D-003). Every write = local apply + `_sync.push(...)`.
  Reads are always served from provider state (that state IS the cache), hydrated from
  the API at boot (`hydratePublic`: outlets+staff) and after login/outlet change
  (`hydrateOutlet`: menu, tables, orders, kots, settings, shift, expenses, customers,
  inventory, suppliers, purchases).
- Server-truth apply (`applyServerTruth`): order json replaces the local order
  (matched by id / client_id / local_id); KOT, table, shift, expense, customer,
  inventory equivalents included. `_activeOrder` pointer follows the replaced object.
- Sync UI state: `isOfflineMode` = engine offline; `pendingSyncCount` = outbox length;
  `lastSyncError`, `lastSyncAt`, `realtimeConnected` exposed.

## Invariants (testable)
- I1: offline pushes enqueue FIFO and persist; a fresh engine replays them in order (restart-safe).
- I2: every replayed POST carries its op id as Idempotency-Key.
- I3: acks replace local state with server state; queued ops referencing local ids are remapped via idmap.
- I4: 4xx rejections drop the op and surface the message; network failures keep it queued.
- I5: SSE order/table/kot/shift events upsert local state without duplicating entities.

## Money
- paise ints on the wire both ways; conversion only in dto.dart.

## Edge cases
- Login while server down → local seeded-staff fallback (demo), flag offline.
- 409 table_occupied on replayed create → error surfaced, local state corrected on next hydrate.
- SSE stream drop → auto-reconnect every 6s; connection state surfaced.
- Web: network printer degrades to no-op (conditional import).

## Test plan
- Unit: outbox round-trip, op id uniqueness, engine FIFO+restart+idmap+error-drop+offline-fallback (MockClient), dto order/settings mapping, EscPos byte layout.
- Live: `tool/api_smoke.dart` against seeded server (login→order→item→qty→KOT→pay→logout).
- Verified: flutter analyze 0 issues; flutter test 24/24 green.

## Open questions
- Q-2 policy: offline PIN verify is demo-seed-only (no client PIN vault in v1).
- Q-5: SSE Last-Event-ID resume not implemented (drop + hydrate-on-reconnect).
