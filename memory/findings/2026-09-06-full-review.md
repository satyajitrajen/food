# Findings — Full Codebase Review (2026-09-06)

Three parallel review passes: models/theme/test, POS flow screens, ops screens.
Status per item: open | fixed | wontfix

## HIGH
- F-01 order_model.dart:31 `unitPrice` sums non-selected modifiers → fixed P0.1
- F-02 order_model.dart Missing `RestaurantOrder.copy()` → fixed P0.1
- F-03 menu_model.dart Missing `MenuItem.copy()`/`ProductVariant.copy()`; mutable ModifierItem leaks → fixed P0.1
- F-04 kot_model.dart:45 `totalQuantity` counts cancelled items → fixed P0.1
- F-05 pos_provider.dart:698,730-731,838 `firstWhere` without orElse (KOT status, cancel item, refund) → fixed P0.2
- F-06 pos_provider.dart:769 completePayment never inserts into `_orders` (paid-without-KOT orders invisible; refund crashes) → fixed P0.2
- F-07 refund_dialog.dart:183 parse failure silently refunds FULL amount; no amount validation; mode discarded → fixed P0.2/P0.3
- F-08 apply_discount_dialog.dart:140 no cap (negative or >100%) → fixed P0.3
- F-09 payment_screen.dart:314 under-tendered cash accepted (changeDue clamped to 0) → fixed P0.3
- F-10 reports_screen.dart fabricated numbers (ratios, fake categories, fake fallbacks) → fixed P0.3
- F-11 close_shift_screen.dart hardcoded denominations (₹7800) overwrite counted cash on first tap → fixed P0.3
- F-12 running_order_detail_screen.dart completed orders show Checkout/Add-Item (double-billing) → fixed P0.3
- F-13 pos_menu_screen.dart:419 minus button firstWhere crash + dead null check → fixed P0.3
- F-14 shift_model.dart:90 refunds subtract from cash drawer regardless of tender → fixed P0.2 (tender-aware refund)

## MED
- F-15 order_model.dart:138 GST base excludes service charge → fixed P0.1
- F-16 order_model.dart no money rounding; float drift → fixed P0.1
- F-17 settings_model.dart all-mutable global settings, no copyWith, silent in-place mutation → fixed P0.1
- F-18 pos_provider.dart:895/901 delete cash expense doesn't reverse shift.expenses → fixed P0.2
- F-19 pos_provider.dart:114 login by PIN not by staff id (PIN collision) → fixed P0.2
- F-20 pos_provider.dart cash in/out accept amount ≤ 0 → fixed P0.2
- F-21 pos_provider.dart:298 merge doesn't re-home secondary's active order → fixed P0.2
- F-22 table_selection_screen.dart:144 reserved/cleaning mutates model directly + duplicate selectTable → fixed P0.3
- F-23 split_bill_dialog.dart shares don't sum (no remainder); split result discarded; count fixed at 3 → fixed P0.3
- F-24 variant_and_modifiers_dialog.dart single-select can't deselect; isRequired never enforced → fixed P0.3
- F-25 merge_tables_dialog.dart overflow (non-scrollable) + can steal table merged elsewhere → fixed P0.3
- F-26 bill_preview_screen.dart invoice date recomputed per rebuild → fixed P0.3
- F-27 cart_view.dart cancelled items → blank rows/stray separators → fixed P0.3
- F-28 add_charge_dialog.dart negative charges accepted → fixed P0.3
- F-29 pos_dashboard_screen.dart AOV mixes shift sales with lifetime orders → fixed P0.3
- F-30 shift_dashboard_screen.dart formula omits refunds; "Open New Shift" hardcodes ₹5000 → fixed P0.3
- F-31 cash_drawer_screen.dart ₹5000 fallback with no shift; Cash In/Out silently no-op → fixed P0.3
- F-32 expense_screen.dart silent validation failure; controller leaks → fixed P0.3
- F-33 pin_login_screen.dart `staffList.first` crash on empty → fixed P0.3
- F-34 running_order_detail_screen.dart takeaway binds arbitrary table (+ .first crash) → fixed P0.3
- F-35 main_adaptive_shell.dart watches entire provider (rebuild storm); desktop/mobile nav indices disconnected → fixed P0.3
- F-36 provider getters return internal mutable lists → fixed P0.2
- F-37 cash_in_out_dialog.dart invalid amounts fail silently → fixed P0.3
- F-38 payment_screen.dart quick-cash chips duplicate at multiples of 500 → fixed P0.3
- F-39 more_hub_screen.dart:110 / open_shift_screen.dart:130 `'${roleTitle}'` renders "null" → fixed P0.3
- F-40 select_outlet_screen.dart hardcoded Online badge → fixed P0.3
- F-41 close_shift_screen.dart empty field falls back to expected (hides shortage); exact float equality → fixed P0.3
- F-42 settings_screen.dart hardcoded floors/seats (48 vs 50) → fixed P0.3
- F-43 stat_kpi_card.dart value text overflow on large amounts → fixed P0.3
- F-44 customer_screen.dart:145 substring(0,1) RangeError on empty name → fixed P0.3
- F-45 dashboard KOT filter compares enum .name to strings → fixed P0.3
- F-46 main_adaptive_shell.dart:171 substring(0,1) on empty name → fixed P0.3
- F-47 pos_provider.dart:601 modifier dedupe ignores itemNote (note lost on merge) → fixed P0.2

## LOW / deferred
- F-48 denominations missing ₹2000/coins → wontfix v1 (documented; backend schema keeps column set, extensible)
- F-49 PIN plaintext (demo) → wontfix now; bcrypt in backend Phase 1 (FR/NFR security)
- F-50 GoogleFonts runtime fetch → open (P4: bundle fonts)
- F-51 widget_test fragility (pumpAndSettle 2s, PNG-for-all mock, floor chip matcher) → open (P2: harden with bundled fonts)
- F-52 customer outstandingCredit dead → open (P3: credit booking)
- F-53 inventory_screen adjust dialog overflow; reason discarded → fixed P0.3 (reason logged in-memory; full audit log P3)
