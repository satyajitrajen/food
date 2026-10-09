# Findings: Emulator UX audit 2026-10-10

Source: full 23-clip emulator audit (Pixel 6 API 36, demo fixture). All
locations verified in source. Fixes follow the approved plan
(bright-tor-sprat); each item flips to `fixed` as its batch lands.

| ID | Severity | Area | Finding | Location | Status |
|---|---|---|---|---|---|
| UX-01 | LOW | Orders | "1 items" / "N Items" / "1 Orders" pluralization across 16 sites | various (batch 1) | fixed |
| UX-02 | MED | KOT | KOT success modal shows "· Takeaway" for Delivery orders (hardcoded binary fallback) | lib/screens/modals/kot_sent_dialog.dart:75 | open |
| UX-03 | MED | Payments | Split-payment receipt shows only first tender ("Cash"); splits never stored on order, backend doesn't echo legs | order_model.dart:131-135, pos_provider.dart:2481, receipt_builder.dart:66 | fixed |
| UX-04 | INFO | Payments | UPI QR placeholder before config — works as designed; add in-box "Not configured" label | payment_screen.dart:651-694 | open |
| UX-05 | MED | Payments | Card approval code collected + stored server-side (payment_reference) but never rendered on receipt | payment_screen.dart:400, dto.dart (missing parse), receipt_builder.dart:66 | fixed |
| UX-06 | MED | Customers | "Add & select" enabled with empty Name (inverted &&/|| logic), tap silently returns | payment_screen.dart:573-577 | open |
| UX-07 | INFO | Orders | No auto delivery charge — works as designed: defaultDeliveryCharge setting defaults to 0 | pos_provider.dart:2022, settings_model.dart:12 | fixed (wontfix — documented) |
| UX-08 | LOW | Staff | "Staff" fallback vs real name inconsistent — dto coerces missing waiter/staff_name to literal 'Staff', defeating UI fallback chains | dto.dart:406,431,513,527,560 | open |
| UX-09 | LOW | Cash | "1 entries" grammar in Cash In/Out Log | cash_drawer_screen.dart:146 | fixed |
| UX-10 | HIGH | Inventory | Record Purchase never updates ingredient stock locally despite "Items received (updates stock):" label (backend applies stock; local mirror missing) | pos_provider.dart:3160-3197 | open |
| UX-11 | MED | Staff | Add Staff empty submit silently returns (bare guard, no feedback) | staff_admin_screen.dart:472 | open |
| UX-12 | MED | Reports | Staff Performance lists all orders under "Unassigned" — only waiter-role creators attributed | pos_provider.dart:2014-2015,1749-1750 | open |
| UX-13 | MED | Reports | Expense total + estimated profit shown unfiltered when order-type filter yields 0 orders (expenses not attributable by type) | reports_screen.dart:239-249,356-401 | open |
| UX-14 | MED | Tables | Add Table empty submit silent no-op | settings_screen.dart:927 | open |
| UX-15 | MED | More hub | Waiter role gets completely empty More tab (0 tiles) | more_hub_screen.dart:35-37 | open |
| UX-16 | LOW | Printing | Print-failure snackbars surface raw SocketException text | pos_provider.dart:3316,3388,3415,3437 | open |
| UX-17 | LOW | KDS | "Preparing (N)" tab label clipped (TabBar not scrollable) | kitchen_board_screen.dart:94-113 | open |
| UX-18 | LOW | Customers | "Customer Directory" title truncates; "Phone · Visits" wraps | customer_screen.dart:336-352,428-430 | open |
| UX-19 | LOW | Docs | flows.md role-tab tables don't match actual tabs (waiter has no Home; kitchen bypasses shell) | docs/flows.md:37-42,142-143 | open |

Notes:
- UX-07 verified wired end-to-end (startNewOrder applies defaultDeliveryCharge;
  totals include it; backend stores delivery_paise). No code change.
- UX-03/05 fix adds backend `payments` echo on single-order GET; design brief
  DB-order-payments-echo.md + decisions.md entry required (API contract change).
