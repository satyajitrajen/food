# Findings: Full product review (mocks, broken features, backend, UI/UX)

- Date: 2026-10-09 · Branch `fix/product-review-2026-10`
- Method: three parallel audits (app mocks/fakes, Go backend, UI/UX + landing). Each HIGH claim was spot-verified in code before fixing.
- Status key: FIXED (on branch) · PARTIAL · OPEN.

## App ↔ server (the root cause of "nothing works")
- **Sync bodies rejected (HIGH).** FIXED. `httpx.Decode` uses DisallowUnknownFields, but app ops sent path ids/local ids in bodies, so payments, refunds, discounts, settings, stock, credit, menu/staff edits and supplier payments all got a 400. The outbox dropped them silently.
  - Fix: `lib/core/sync/op_specs.dart` builds each body from an allowlist.
  - Guard: `contracts/sync_ops.json`, tested from both Dart and Go.
- **Online pushes not serialized (HIGH).** FIXED. add_item raced order.create, item ids were never mapped, and the id map was in memory only. The sync engine is now one FIFO queue with a persisted id map and item-id mapping.
- **Rejected writes invisible (HIGH).** FIXED. 401/402/5xx/429 now park the queue instead of dropping writes. 4xx rejections roll back and appear in the sync panel.

## Mocks / fake data (user priority)
- **App seed data (HIGH).** FIXED. About 1,100 lines removed: outlets, 17 staff with plaintext PINs, tables, the 57-item menu, the Green Candle clone, expenses, customers, suppliers and purchases. Tests use `test/fixtures/pos_fixtures.dart`.
- **Fake restaurant identity on bills (HIGH).** FIXED. "Spice Haven", fake GSTIN/FSSAI and fake printers are gone. Bills use the outlet record, editable through PATCH /outlets/{id}.
- **Fake successes (HIGH).** FIXED: "Z-report sent to printer", "Synced successfully", NullPrinter returning true, "PineLabs", credit recorded as cash, and the "Simulate offline" switch.
- **Invented numbers (MED).** FIXED. Local ORD-1045/INV-1045/KOT #1204 are gone; invoice numbers are server-assigned.
- **Backend seed in server binary (HIGH).** See backend section.
- **Landing (MED).** FIXED: invented testimonials, fake store badges, unsupported feature claims, FoodPOS/orange brand split, and 13 MB of unused images.

## Features that didn't work (app)
All FIXED unless noted:
- Takeaway/delivery orders couldn't be created.
- Split tender had no UI.
- Card reference was dropped.
- Ghost orders were created on every table tap.
- GST, charges, printers and profile were read-only.
- 5–6 digit PINs couldn't log in.
- Outlet switch got a 403 on every request.
- New org couldn't add its first menu item.
- Price edit rounded to whole rupees.
- Shift close was not blind, had no ₹20/₹10/coins rows, faked the Z-report print, and didn't log out.
- Reports splits were always zero (`_paiseMapToRupees`).
- Report ranges were never cached.
- Tablets couldn't reach More (Menu/Staff/Printer/Cash drawer/...).
- Refund was capped by cash tendered.

## UI/UX
FIXED:
- WCAG contrast: brand green for text and buttons is now #067A37; textLight, amber and red darkened.
- ₹ Indian grouping via formatInr (86 sites).
- Merged Bill & Payment screen with no redundant confirm.
- One-tap add for simple dishes.
- Navigation rail for 600–1024 px.
- Pull-to-refresh and empty states.
- Tooltips on 31 icon buttons.
- "Counter Counter 1" and "Table Counter" labels.
- Guest details can be skipped.
- Single-choice add-ons behave as radios.

OPEN (deferred, larger refactors):
- Dark theme. Screens use static AppColors in const widgets.
- l10n/ARB extraction.
- Tablet split view (menu + cart side panel).
- KDS multi-column grid.
- About 150 hard-coded `Colors.white` surfaces.

## Backend
Summary to be completed from the backend agent's report: dead features, cross-tenant holes, money integrity, seed removal and admin import, reports/time zone, performance.
