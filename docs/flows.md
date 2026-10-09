# ReadyKOT POS — Complete Flows Map

---

## 1. Top-Level Navigation Structure

The app uses `MaterialApp` with **no named routes**. All navigation is imperative via `Navigator.of(context).push(MaterialPageRoute(builder: ...))` or `pushReplacement` / `pushAndRemoveUntil`.

### Responsive Shell (`MainAdaptiveShell`)

| Breakpoint | Layout |
|---|---|
| < 600 px (mobile) | Bottom `NavigationBar` |
| 600–1024 px (tablet) | `NavigationRail` |
| > 1024 px (desktop) | Persistent sidebar |

The shell is driven by the `AppDest` enum (`lib/models/app_nav.dart`):

| AppDest value | Label | Icon |
|---|---|---|
| `dashboard` | Home | `dashboard` |
| `runningOrders` | Orders | `receipt_long` |
| `pos` | POS | `point_of_sale` |
| `tables` | Tables | `table_restaurant` |
| `kitchen` | Kitchen | `chef_hat` |
| `transactions` | Transactions | `history` |
| `shiftCash` | Shift & Cash | `savings` |
| `expenses` | Expenses | `receipt` |
| `customers` | Customers | `people` |
| `inventory` | Inventory | `inventory_2` |
| `reports` | Reports | `analytics` |
| `settings` | Settings | `settings` |
| `more` | More | `more_horiz` |

### Role-Based Tab Visibility (Mobile)

| Role | Bottom-bar tabs |
|---|---|
| `admin` | dashboard, runningOrders, pos, tables, more |
| `manager` / `cashier` | pos, runningOrders, tables, more |
| `waiter` | tables, runningOrders, pos, more |
| `kitchen` | bypasses the shell entirely → full-screen `KitchenBoardScreen` |

Desktop/tablet show the full role-filtered destination list in sidebar/rail (canonical source: `PosProvider.navDestinations`, `lib/providers/pos_provider.dart` ~:1138); the `MoreHubScreen` enforces role filtering on tile visibility.

---

## 2. Auth Gate Logic

### `SplashScreen` (`lib/screens/auth/splash_screen.dart`)

Waits for `provider.ready` (up to 10 s) + 1500 ms splash delay, then:

```
if !provider.ready           → stay on splash (timeout message)
if provider.needsOrgSetup    → OrgRegistrationScreen  (pushReplacement)
if currentStaff.role == kitchen → KitchenBoardScreen   (pushReplacement)
if currentStaff.role == waiter OR provider.hasOpenShift → MainAdaptiveShell (pushReplacement)
else                         → OpenShiftScreen         (pushReplacement)
if no staff logged in        → PinLoginScreen           (pushReplacement)
```

### `PinLoginScreen` (`lib/screens/auth/pin_login_screen.dart`)

- 4–6 digit PIN entry with auto-submit at max length
- Staff picker bottom sheet lists active staff; tap to select, then enter PIN
- On success → `provider.loginStaff(pin)` → navigates per auth gate logic above
- "Switch Outlet" link → `SelectOutletScreen`

---

## 3. Route Table (All Screens)

| # | Screen Widget | File | Entered From |
|---|---|---|---|
| 1 | `SplashScreen` | `lib/screens/auth/splash_screen.dart` | App launch (set as `MaterialApp.home`) |
| 2 | `PinLoginScreen` | `lib/screens/auth/pin_login_screen.dart` | SplashScreen (no staff), MainAdaptiveShell "Lock Register", ShiftDashboard "Lock Register" |
| 3 | `OrgRegistrationScreen` | `lib/screens/auth/org_registration_screen.dart` | SplashScreen (needsOrgSetup) |
| 4 | `OrgSetupScreen` | `lib/screens/auth/org_setup_screen.dart` | OrgRegistrationScreen (after submit) |
| 5 | `SelectOutletScreen` | `lib/screens/auth/select_outlet_screen.dart` | PinLoginScreen "Switch Outlet" |
| 6 | `MainAdaptiveShell` | `lib/screens/shell/main_adaptive_shell.dart` | SplashScreen (auth OK), OpenShiftScreen (shift opened), PinLoginScreen (login OK) |
| 7 | `OpenShiftScreen` | `lib/screens/shift/open_shift_screen.dart` | SplashScreen (no open shift) |
| 8 | `PosMenuScreen` | `lib/screens/pos_menu/pos_menu_screen.dart` | Shell → POS tab |
| 9 | `TableSelectionScreen` | `lib/screens/order_flow/table_selection_screen.dart` | Shell → Tables tab, PosMenuScreen "Select Table", KOT Sent dialog "Floor Tables" |
| 10 | `CartViewScreen` | `lib/screens/cart/cart_view.dart` | PosMenuScreen (item added to cart), TableSelectionScreen (start order) |
| 11 | `PaymentScreen` | `lib/screens/payment/payment_screen.dart` | CartViewScreen "Proceed to Payment" |
| 12 | `PaymentSuccessScreen` | `lib/screens/receipt/payment_success_screen.dart` | PaymentScreen (payment complete), TransactionsScreen "View Bill" |
| 13 | `PosDashboardScreen` | `lib/screens/dashboard/pos_dashboard_screen.dart` | Shell → Home tab |
| 14 | `KitchenBoardScreen` | `lib/screens/kitchen/kitchen_board_screen.dart` | Shell → Kitchen tab, SplashScreen (kitchen role) |
| 15 | `RunningOrdersScreen` | `lib/screens/running_orders/running_orders_screen.dart` | Shell → Orders tab |
| 16 | `RunningOrderDetailScreen` | `lib/screens/running_orders/running_order_detail_screen.dart` | RunningOrdersScreen (tap order), ReadyToServeScreen (tap order) |
| 17 | `ReadyToServeScreen` | `lib/screens/running_orders/ready_to_serve_screen.dart` | Shell → Orders tab (waiter), RunningOrdersScreen tab switch |
| 18 | `CloseShiftScreen` | `lib/screens/shift/close_shift_screen.dart` | ShiftDashboardScreen "Close Shift" |
| 19 | `ShiftDashboardScreen` | `lib/screens/shift/shift_dashboard_screen.dart` | Shell → Shift & Cash tab |
| 20 | `CashDrawerScreen` | `lib/screens/cash_drawer/cash_drawer_screen.dart` | Shell → Shift & Cash tab, ShiftDashboardScreen "View Drawer" |
| 21 | `SettingsScreen` | `lib/screens/settings/settings_screen.dart` | Shell → Settings tab |
| 22 | `MenuAdminScreen` | `lib/screens/settings/menu_admin_screen.dart` | SettingsScreen "Manage Menu" |
| 23 | `StaffAdminScreen` | `lib/screens/settings/staff_admin_screen.dart` | SettingsScreen "Manage Staff" |
| 24 | `ReportsScreen` | `lib/screens/reports/reports_screen.dart` | Shell → Reports tab |
| 25 | `InventoryScreen` | `lib/screens/inventory/inventory_screen.dart` | Shell → Inventory tab |
| 26 | `ExpenseScreen` | `lib/screens/expenses/expense_screen.dart` | Shell → Expenses tab |
| 27 | `CustomerScreen` | `lib/screens/customers/customer_screen.dart` | Shell → Customers tab |
| 28 | `TransactionsScreen` | `lib/screens/transactions/transactions_screen.dart` | Shell → Transactions tab |
| 29 | `PrinterStatusScreen` | `lib/screens/printer/printer_status_screen.dart` | SettingsScreen "Printer Status" |
| 30 | `MoreHubScreen` | `lib/screens/more/more_hub_screen.dart` | Shell → More tab |
| 31 | `AttendanceScreen` | `lib/screens/more/attendance_screen.dart` | MoreHubScreen "Attendance" |
| 32 | `CustomerMenuQrScreen` | `lib/screens/more/customer_menu_qr_screen.dart` | MoreHubScreen "Customer Menu QR" |

---

## 4. Modal Dialogs Table

| # | Modal Widget | File | Opened From |
|---|---|---|---|
| M1 | `ManagerPinDialog` | `lib/screens/modals/manager_pin_dialog.dart` | ApplyDiscountDialog, CancelItemDialog, RefundDialog, StaffAdminScreen (PIN reset) |
| M2 | `GuestDetailsDialog` | `lib/screens/modals/guest_details_dialog.dart` | TableSelectionScreen (tap available table) |
| M3 | `VariantAndModifiersDialog` | `lib/screens/modals/variant_and_modifiers_dialog.dart` | PosMenuScreen (tap menu item with variants/modifiers) |
| M4 | `KotPreviewDialog` | `lib/screens/modals/kot_preview_dialog.dart` | CartViewScreen "Send KOT" |
| M5 | `KotSentDialog` | `lib/screens/modals/kot_sent_dialog.dart` | After KOT successfully sent (cart_view) |
| M6 | `AddChargeDialog` | `lib/screens/modals/add_charge_dialog.dart` | PaymentScreen "Charges" |
| M7 | `ApplyDiscountDialog` | `lib/screens/modals/apply_discount_dialog.dart` | PaymentScreen "Discount" |
| M8 | `CancelItemDialog` | `lib/screens/modals/cancel_item_dialog.dart` | RunningOrderDetailScreen (cancel item icon) |
| M9 | `CashInOutDialog` | `lib/screens/modals/cash_in_out_dialog.dart` | ShiftDashboardScreen, CashDrawerScreen |
| M10 | `MergeTablesDialog` | `lib/screens/modals/merge_tables_dialog.dart` | TableSelectionScreen (merge action) |
| M11 | `MoveTableDialog` | `lib/screens/modals/move_table_dialog.dart` | TableSelectionScreen (move action on occupied table) |
| M12 | `OfflineSyncDialog` | `lib/screens/modals/offline_sync_dialog.dart` | MoreHubScreen "Sync Status", SettingsScreen |
| M13 | `PrinterErrorDialog` | `lib/screens/modals/printer_error_dialog.dart` | PaymentScreen (print fail), CartViewScreen (KOT print fail) |
| M14 | `RefundDialog` | `lib/screens/modals/refund_dialog.dart` | TransactionsScreen "Refund" |

---

## 5. Role / Permission Gates

| Gate | Who | Operations |
|---|---|---|
| `canManage` | `admin` or `manager` | Menu editing, staff editing, settings changes, expense deletion, inventory adjustments |
| Manager PIN | Any user with valid manager/admin PIN | High discounts (>20% or >₹500), item cancellation, credit payments, PIN resets, refunds |
| Owner protection (`isProtected`) | Only the owner themselves | Role change, status toggle, PIN reset for owner account |
| Manager cannot edit admin rows | `manager` role | Cannot change role/status/PIN of admin staff |
| Reprint allowed | `settings.allowReprint` | Controls whether "Print" button appears on TransactionsScreen |
| Cashier tab restriction | `cashier` role | No access to Dashboard or Reports (admin-only revenue area); other destinations live on the desktop rail / More hub |
| Waiter tab restriction | `waiter` role | Only Tables, Orders, POS, More — no dashboard; More hub shows 3 safe tiles with money actions hidden |
| Kitchen tab restriction | `kitchen` role | No shell destinations; login bypasses the shell entirely → full-screen `KitchenBoardScreen` |

---

## 6. Flows — Screen by Screen

---

### 6.1 Entry / Shell

---

#### `SplashScreen`

- **Purpose**: App entry point; waits for PosProvider initialization, then routes based on auth state.
- **Entered from**: App launch (`MaterialApp.home`).
- **UI sections**: App logo/branding, loading indicator, timeout message if `provider.ready` takes >10 s.
- **Actions/Exits**:
  - `provider.ready == true` → evaluates auth gate decision tree (see Section 2).
  - Navigation: `pushReplacement` to one of: `OrgRegistrationScreen`, `KitchenBoardScreen`, `MainAdaptiveShell`, `OpenShiftScreen`, `PinLoginScreen`.
- **State consumed**: `PosProvider` — `ready`, `needsOrgSetup`, `currentStaff`, `hasOpenShift`.

---

#### `PinLoginScreen`

- **Purpose**: Staff authentication via 4–6 digit PIN.
- **Entered from**: `SplashScreen` (no staff logged in), `MainAdaptiveShell` "Lock Register", `ShiftDashboardScreen` "Lock Register".
- **UI sections**:
  - PIN entry field with numeric keypad (auto-submit at 4 or 6 digits).
  - Staff picker bottom sheet (lists active staff, tap to select).
  - "Switch Outlet" text button at bottom.
- **Actions**:
  - PIN auto-submits → `provider.verifyPin(pin)` → on success, `provider.loginStaff(staff)` → navigates per auth gate.
  - "Switch Outlet" → `SelectOutletScreen`.
- **Exits**: On successful login → `MainAdaptiveShell` or role-specific screen. On cancel → stays on screen.
- **State consumed**: `PosProvider` — `activeStaff`, `outlets`, `verifyPin()`, `loginStaff()`.

---

#### `OrgRegistrationScreen`

- **Purpose**: SaaS self-service organization registration (first-time setup).
- **Entered from**: `SplashScreen` when `provider.needsOrgSetup == true`.
- **UI sections**: Organization name, owner name, email, phone, password fields.
- **Actions**:
  - "Register" → `provider.registerOrg(...)` → on success → `OrgSetupScreen`.
- **Exits**: → `OrgSetupScreen`.
- **State consumed**: `PosProvider` — `registerOrg()`.

---

#### `OrgSetupScreen`

- **Purpose**: Terminal binding — enter organization join code to link this device to an org.
- **Entered from**: `OrgRegistrationScreen` (after successful registration).
- **UI sections**: Join code input field, "Link Terminal" button.
- **Actions**:
  - "Link Terminal" → `provider.linkTerminal(code)` → on success → `PinLoginScreen`.
- **Exits**: → `PinLoginScreen`.
- **State consumed**: `PosProvider` — `linkTerminal()`.

---

#### `SelectOutletScreen`

- **Purpose**: List available outlets for the organization; tap to switch.
- **Entered from**: `PinLoginScreen` "Switch Outlet".
- **UI sections**: List of outlets with name and address.
- **Actions**:
  - Tap outlet → `provider.selectOutlet(outlet)` → pops back to `PinLoginScreen`.
- **Exits**: Pop back to `PinLoginScreen`.
- **State consumed**: `PosProvider` — `outlets`, `selectOutlet()`.

---

#### `MainAdaptiveShell`

- **Purpose**: Role-aware responsive shell wrapping all main app destinations.
- **Entered from**: `SplashScreen` (auth OK), `OpenShiftScreen` (shift opened), `PinLoginScreen` (login OK).
- **UI sections**:
  - Navigation shell (bottom nav / rail / sidebar per breakpoint).
  - Body: `_screenFor(AppDest)` renders the selected destination.
  - AppBar with outlet name, sync status indicator (`pendingSyncCount`), user name.
- **Actions**:
  - Tab/destination tap → switches active `AppDest`.
  - "Lock Register" (in AppBar or overflow) → `PinLoginScreen` (pushReplacement, clears stack).
  - Sync status indicator → `OfflineSyncDialog`.
- **Exits**: "Lock Register" → `PinLoginScreen`.
- **State consumed**: `PosProvider` — `currentStaff`, `outlet`, `pendingSyncCount`, `isOfflineMode`.

---

### 6.2 Auth / Onboarding

(Covered above: SplashScreen, PinLoginScreen, OrgRegistrationScreen, OrgSetupScreen, SelectOutletScreen.)

---

### 6.3 POS / Ordering Flow

---

#### `PosMenuScreen`

- **Purpose**: Menu grid for building an order; search, category filter, veg filter.
- **Entered from**: Shell → POS tab.
- **UI sections**:
  - Search bar at top.
  - Category chip row (horizontal scroll).
  - Veg-only toggle switch.
  - Menu item grid (cards with name, price, veg mark, photo).
- **Actions**:
  - Tap menu item → if item `hasVariants` or `hasModifiers` → `VariantAndModifiersDialog`; else → adds directly to cart.
  - Cart badge shows item count; tap → `CartViewScreen`.
  - "Select Table" button (if no table selected) → `TableSelectionScreen`.
- **Exits**: → `CartViewScreen`, `TableSelectionScreen`, or opens `VariantAndModifiersDialog`.
- **State consumed**: `PosProvider` — `menuItems`, `cart`, `selectedTable`, `activeOrder`.

---

#### `TableSelectionScreen`

- **Purpose**: Floor plan / table grid for selecting or managing tables.
- **Entered from**: Shell → Tables tab, PosMenuScreen "Select Table", KOT Sent dialog "Floor Tables".
- **UI sections**:
  - Floor/section chip row.
  - Status filter (All / Available / Occupied / Reserved).
  - Table grid: each table card shows number, seats, status color, active order info.
- **Actions**:
  - Tap **available** table → `GuestDetailsDialog` (opens as bottom sheet/dialog).
  - Tap **occupied** table → opens active order (→ `CartViewScreen` or `RunningOrderDetailScreen`).
  - AppBar merge icon (on occupied table) → `MergeTablesDialog`.
  - AppBar move icon (on occupied table) → `MoveTableDialog`.
- **Exits**: → `GuestDetailsDialog`, `CartViewScreen`, `MergeTablesDialog`, `MoveTableDialog`.
- **State consumed**: `PosProvider` — `tables`, `orders`, `floors`.

---

#### `CartViewScreen`

- **Purpose**: Current order cart — item list with qty controls, order note, totals.
- **Entered from**: PosMenuScreen (cart badge tap), TableSelectionScreen (start order after guest details).
- **UI sections**:
  - Item list: each row has name, variant, modifiers, qty stepper (+/−), line total, delete icon.
  - Order note field.
  - Subtotal, tax, discount, grand total breakdown.
  - Bottom bar: "Send KOT" button, "Hold Order" button, "Proceed to Payment" button.
- **Actions**:
  - Qty +/− → `provider.updateCartQty(item, qty)`.
  - Delete icon → removes item from cart.
  - "Send KOT" → `KotPreviewDialog` → on confirm → `provider.sendKOT()` → `KotSentDialog`.
  - "Proceed to Payment" → `PaymentScreen`.
  - "Hold Order" → `provider.holdOrder()`.
- **Modals opened**: `KotPreviewDialog`, `KotSentDialog`.
- **Exits**: → `PaymentScreen`, or pop back to PosMenuScreen/TableSelectionScreen.
- **State consumed**: `PosProvider` — `cart`, `activeOrder`, `currentStaff`, `settings` (tax config).

---

#### `PaymentScreen`

- **Purpose**: Bill review and payment collection.
- **Entered from**: CartViewScreen "Proceed to Payment".
- **UI sections**:
  - Order summary: items, subtotal, taxes, discounts, charges, grand total.
  - Payment mode buttons: Cash, UPI, Card, Credit.
  - "Charges" button → `AddChargeDialog`.
  - "Discount" button → `ApplyDiscountDialog`.
  - Cash payment: tendered amount input, change calculation.
  - UPI payment: QR code display, "Mark as Received" button.
  - Credit payment: customer selection, requires Manager PIN.
- **Actions**:
  - "Charges" → `AddChargeDialog`.
  - "Discount" → `ApplyDiscountDialog`.
  - Cash "Complete Payment" → `provider.processPayment(...)` → `PaymentSuccessScreen`.
  - UPI "Mark as Received" → `provider.processPayment(...)` → `PaymentSuccessScreen`.
  - Credit → `ManagerPinDialog` → `provider.processPayment(...)` → `PaymentSuccessScreen`.
  - Print fails → `PrinterErrorDialog`.
- **Modals opened**: `AddChargeDialog`, `ApplyDiscountDialog`, `ManagerPinDialog` (credit), `PrinterErrorDialog`.
- **Exits**: → `PaymentSuccessScreen` (pushAndRemoveUntil to shell), or pop back to CartViewScreen.
- **State consumed**: `PosProvider` — `cart`, `activeOrder`, `settings` (UPI QR, taxes), `processPayment()`.

---

#### `PaymentSuccessScreen`

- **Purpose**: Receipt display after successful payment; share/print options.
- **Entered from**: PaymentScreen (payment complete), TransactionsScreen "View Bill".
- **UI sections**:
  - Success checkmark animation.
  - Receipt: restaurant name, invoice number, date, items, totals, payment method, change.
  - "Share Receipt" button, "Print Receipt" button, "New Order" button, "Done" button.
- **Actions**:
  - "Share Receipt" → platform share sheet.
  - "Print Receipt" → `provider.printReceipt()`.
  - "New Order" → pops back to shell (POS tab).
  - "Done" → pops back to shell.
- **Exits**: Pop back to `MainAdaptiveShell`.
- **State consumed**: `PosProvider` — `lastCompletedOrder`, `printReceipt()`.

---

### 6.4 Kitchen / Running Orders

---

#### `KitchenBoardScreen`

- **Purpose**: Kitchen display system — 4-tab KOT board for kitchen staff.
- **Entered from**: Shell → Kitchen tab, SplashScreen (kitchen role direct launch).
- **UI sections**:
  - 4 tabs: "New" (pending KOTs), "In Progress", "Ready", "Completed".
  - Each tab shows KOT cards: table number, items, time elapsed, priority indicators.
  - Tap KOT card → status transition (New → In Progress → Ready → Completed).
- **Actions**:
  - Tap KOT card → `provider.advanceKotStatus(kotId)`.
  - Pull-to-refresh → `provider.refreshKitchen()`.
- **Exits**: Back button → shell (or lock screen).
- **State consumed**: `PosProvider` — `kitchenTickets`, `advanceKotStatus()`.

---

#### `RunningOrdersScreen`

- **Purpose**: Live order tracking — 2 tabs for floor management.
- **Entered from**: Shell → Orders tab.
- **UI sections**:
  - Tab "All": all active orders (dine-in, takeaway, delivery).
  - Tab "Dine-In": only dine-in orders with table numbers.
  - Each order card: order number, table, type, time, status, item count.
- **Actions**:
  - Tap order card → `RunningOrderDetailScreen`.
  - Tab switch → filters list.
  - Pull-to-refresh → `provider.triggerSync()`.
- **Exits**: → `RunningOrderDetailScreen`.
- **State consumed**: `PosProvider` — `orders`, `activeOrders`.

---

#### `RunningOrderDetailScreen`

- **Purpose**: Detailed view of a single running order.
- **Entered from**: RunningOrdersScreen (tap order), ReadyToServeScreen (tap order).
- **UI sections**:
  - Order header: order number, table, type, status, time.
  - Item list: name, variant, modifiers, qty, status (sent/prepared/served).
  - Order note displayed.
  - Per-item cancel icon (for active items).
- **Actions**:
  - Cancel item icon → `CancelItemDialog` → on confirm with manager PIN → `provider.cancelItem(orderId, itemId, reason, pin)`.
  - "Print KOT" → `provider.printKOT()`.
- **Modals opened**: `CancelItemDialog` (which opens `ManagerPinDialog`).
- **Exits**: Pop back to RunningOrdersScreen/ReadyToServeScreen.
- **State consumed**: `PosProvider` — `orders`, `cancelItem()`.

---

#### `ReadyToServeScreen`

- **Purpose**: Waiter queue — orders marked ready by kitchen, awaiting service.
- **Entered from**: Shell → Orders tab (waiter role), RunningOrdersScreen tab.
- **UI sections**:
  - List of orders with "Ready" status.
  - Each card: order number, table, items, time since ready.
- **Actions**:
  - Tap order → `RunningOrderDetailScreen`.
  - "Mark Served" → `provider.markServed(orderId)`.
  - Pull-to-refresh → `provider.refreshReadyOrders()`.
- **Exits**: → `RunningOrderDetailScreen`.
- **State consumed**: `PosProvider` — `readyOrders`, `markServed()`.

---

### 6.5 Shift / Cash

---

#### `OpenShiftScreen`

- **Purpose**: Open a new cash shift — record opening float.
- **Entered from**: SplashScreen (no open shift).
- **UI sections**:
  - Opening cash amount input (numeric).
  - Denomination breakdown (optional): notes/coins count.
  - "Open Shift" button.
- **Actions**:
  - "Open Shift" → `provider.openShift(float, denominations)` → on success → `MainAdaptiveShell` (pushReplacement).
- **Exits**: → `MainAdaptiveShell`.
- **State consumed**: `PosProvider` — `openShift()`.

---

#### `ShiftDashboardScreen`

- **Purpose**: Shift KPIs and cash management during an active shift.
- **Entered from**: Shell → Shift & Cash tab.
- **UI sections**:
  - Shift header: opened by, open time, current duration.
  - KPI cards: total sales, cash sales, UPI sales, card sales, order count, avg order value.
  - "Cash In" button → `CashInOutDialog(kind: 'in')`.
  - "Cash Out" button → `CashInOutDialog(kind: 'out')`.
  - "View Drawer" → `CashDrawerScreen`.
  - "Close Shift" → `CloseShiftScreen`.
  - "Lock Register" → `PinLoginScreen`.
- **Modals opened**: `CashInOutDialog`.
- **Exits**: → `CashDrawerScreen`, `CloseShiftScreen`, `PinLoginScreen`.
- **State consumed**: `PosProvider` — `currentShift`, `shiftStats`, `addCashIn()`, `addCashOut()`.

---

#### `CloseShiftScreen`

- **Purpose**: Blind cash count and Z-report generation to close the shift.
- **Entered from**: ShiftDashboardScreen "Close Shift".
- **UI sections**:
  - Expected cash vs actual count input (denomination breakdown).
  - Variance display (over/short).
  - Z-report summary: total sales, payments by mode, cash in/out, voids, refunds.
  - "Close Shift" button.
- **Actions**:
  - "Close Shift" → `provider.closeShift(counts)` → on success → `PinLoginScreen` (pushAndRemoveUntil, clears stack).
- **Exits**: → `PinLoginScreen` (full stack clear).
- **State consumed**: `PosProvider` — `currentShift`, `shiftStats`, `closeShift()`.

---

#### `CashDrawerScreen`

- **Purpose**: Expected cash breakdown for the current shift/drawer.
- **Entered from**: Shell → Shift & Cash tab, ShiftDashboardScreen "View Drawer".
- **UI sections**:
  - Expected cash total.
  - Denomination breakdown: each note/coin count × value.
  - Cash In/Out history list.
  - "Cash In" button → `CashInOutDialog(kind: 'in')`.
  - "Cash Out" button → `CashInOutDialog(kind: 'out')`.
- **Modals opened**: `CashInOutDialog`.
- **Exits**: Pop back to ShiftDashboardScreen or shell.
- **State consumed**: `PosProvider` — `currentShift`, `cashMovements`, `drawerBalance`.

---

### 6.6 Management / Settings

---

#### `SettingsScreen`

- **Purpose**: Restaurant configuration hub — profile, taxes, UPI, printers, tables, menu, staff.
- **Entered from**: Shell → Settings tab.
- **UI sections**:
  - Restaurant profile (name, address, phone).
  - Tax configuration (GST/VAT rates).
  - UPI settings (QR, VPA ID).
  - Printer configuration (name, host:port, connection test).
  - Table/floor management.
  - "Manage Menu" → `MenuAdminScreen`.
  - "Manage Staff" → `StaffAdminScreen`.
  - Subscription card (admin only) → `SubscriptionCard` widget inline.
  - "Printer Status" → `PrinterStatusScreen`.
  - Sync status → `OfflineSyncDialog`.
- **Actions**:
  - Edit fields → `provider.updateSettings(...)`.
  - "Manage Menu" → `MenuAdminScreen`.
  - "Manage Staff" → `StaffAdminScreen`.
  - "Printer Status" → `PrinterStatusScreen`.
  - All edits gated by `provider.canManage`.
- **Modals opened**: `OfflineSyncDialog`.
- **Exits**: → `MenuAdminScreen`, `StaffAdminScreen`, `PrinterStatusScreen`.
- **State consumed**: `PosProvider` — `settings`, `canManage`, `updateSettings()`.

---

#### `MenuAdminScreen`

- **Purpose**: Full menu CRUD — add/edit/delete items, availability toggle, photo upload, variant and modifier-group editing.
- **Entered from**: SettingsScreen "Manage Menu".
- **UI sections**:
  - Menu item list grouped by category.
  - Each item: name, price, photo, availability switch, edit icon, delete icon.
  - AppBar "+" → add new item.
  - Non-manager banner: "Manager/Admin login required to edit the menu (view only)."
- **Actions**:
  - "+" → `_showEditDialog` (add mode).
  - Edit icon → `_showEditDialog(context, item)` (edit mode).
  - Delete icon → `_confirmDelete` → `provider.deleteMenuItem(item.id)`.
  - Availability switch → `provider.toggleAvailability(item.id)`.
  - All edit actions gated by `provider.canManage`.
- **Edit dialog** (`_showEditDialog`):
  - Inputs: name, category (ChoiceChips), price, description, veg/non-veg switch, bestseller switch, photo upload (ImagePicker).
  - "Edit Variants" → `_VariantsEditorDialog` (sub-dialog: list of variant rows with name + price, add/remove). Returns `List<ProductVariant>`.
  - "Edit Add-On Groups" → `_ModifierGroupsEditorDialog` (sub-dialog: list of groups, each with name, multi-select switch, required switch, option rows with name + price). Returns `List<ModifierGroup>`.
  - "Save" → `provider.addMenuItem(...)` or `provider.updateMenuItem(...)`.
- **Exits**: Pop back to SettingsScreen.
- **State consumed**: `PosProvider` — `menuItems`, `canManage`, `addMenuItem()`, `updateMenuItem()`, `deleteMenuItem()`, `toggleAvailability()`.

---

#### `StaffAdminScreen`

- **Purpose**: Staff directory management — add, edit, toggle active, change role, reset PIN.
- **Entered from**: SettingsScreen "Manage Staff".
- **UI sections**:
  - Staff list: name, role badge, active/inactive status, outlet assignment.
  - AppBar "+" → add new staff.
  - Per-staff popup menu: change role, toggle status, reset PIN, edit details.
- **Actions**:
  - "+" → `_showAddDialog`: name, PIN (4–6 digits), mobile (optional), role dropdown, outlet assignment (required for waiter/kitchen). Managers cannot create admin staff.
  - Popup "Edit" → `_showEditDialog`: name, mobile, role, outlet. Role change blocked for self/owner/admin-by-manager.
  - Popup "Reset PIN" → `_showPinResetDialog`: new PIN entry. Owner target requires self-only. Non-owner targets require `ManagerPinDialog` authorization.
  - Popup "Change Role" → `_pickRoleChange` (SimpleDialog with StaffRole.values) → `_confirmRoleChange` (showConfirmDialog).
  - Popup "Toggle Active" → `provider.toggleStaffActive(staff)`.
  - Owner protection: `isProtected` staff only editable by self.
- **Modals opened**: `ManagerPinDialog` (for non-owner PIN resets).
- **Exits**: Pop back to SettingsScreen.
- **State consumed**: `PosProvider` — `staff`, `canManage`, `currentStaff`, `addStaff()`, `updateStaff()`, `toggleStaffActive()`, `resetStaffPin()`, `changeStaffRole()`.

---

#### `SubscriptionCard` (widget inside SettingsScreen)

- **Purpose**: Subscription management — plan info, status, auto-renew, billing actions (admin only).
- **Entered from**: Rendered inline on SettingsScreen.
- **UI sections**:
  - Plan name, status badge, auto-renew toggle, trial info, pricing.
  - "Enable auto-pay" / "auto-renew" button.
  - "Pay one cycle now" button.
  - "Cancel auto-renew" button.
- **Actions**:
  - "Enable auto-pay" → `_askOwnerToken` (dialog: owner email + password → token) → Razorpay checkout → `provider.enableAutoRenew(token)`.
  - "Pay one cycle now" → `_askOwnerToken` → Razorpay checkout → `provider.payOneCycle(token)`.
  - "Cancel auto-renew" → confirm → `provider.cancelAutoRenew()`.
- **State consumed**: `PosProvider` — `subscription`, `enableAutoRenew()`, `payOneCycle()`, `cancelAutoRenew()`.

---

#### `ReportsScreen`

- **Purpose**: Reports and analytics with period and order-type filters.
- **Entered from**: Shell → Reports tab.
- **UI sections**:
  - Period filter chips: Today / 7D / 30D / All / Custom.
  - Order type filter: All / Dine-In / Takeaway / Delivery.
  - Summary stat chips: orders, AOV, net sales, expenses.
  - Estimated Profit card.
  - Sales by Order Type chart.
  - Payment Mode Distribution chart.
  - Top Performing Categories list.
  - Top Selling Items list.
  - Staff Performance list.
  - Expenses by Category breakdown.
- **Actions**:
  - "Custom" period → `showDateRangePicker`.
  - Pull-to-refresh → `provider.fetchServerReport(range)`.
  - Uses `provider.serverRangeReport` when available, local fallback.
- **Exits**: Back to shell.
- **State consumed**: `PosProvider` — `serverRangeReport`, `orders`, `expenses`, `fetchServerReport()`.

---

#### `InventoryScreen`

- **Purpose**: Inventory management — 5 tabs for ingredients, stock, suppliers, purchases, log.
- **Entered from**: Shell → Inventory tab.
- **UI sections**:
  - Tab "Ingredients": item list with name, unit, current stock, min stock, cost. Low-stock items highlighted.
  - Tab "Low Stock": filtered view of items below minimum.
  - Tab "Suppliers": supplier cards with outstanding balance, payment history.
  - Tab "Purchases": purchase records with invoice, supplier, date, status (paid/pending).
  - Tab "Stock Log": chronological stock movement entries.
- **Actions**:
  - AppBar "+" → `_showAddItemDialog`: name, unit, opening stock, min stock, cost, batch no, rack no, purchase date.
  - "Adjust" button per item → `_showAdjustStockDialog`: increase/decrease, qty, reason dropdown.
  - Suppliers tab FAB "Add Supplier" → `_showAddSupplierDialog`.
  - Supplier "Make Payment" → `_showSupplierPaymentDialog`: amount, method chips, date, reference.
  - Purchases tab FAB "Record Purchase" → `_showPurchaseDialog`: invoice, supplier, date, paid/pending, item search with qty/cost.
  - Pending purchases "Mark Paid" → `provider.markPurchasePaid(purchaseId)`.
  - Pull-to-refresh on Stock Log tab.
- **Exits**: Back to shell.
- **State consumed**: `PosProvider` — `inventoryItems`, `suppliers`, `purchases`, `stockLog`, `canManage`.

---

#### `ExpenseScreen`

- **Purpose**: Expense tracking with period filter and KPI cards.
- **Entered from**: Shell → Expenses tab.
- **UI sections**:
  - Period filter: Today / 7D / 30D / All / Custom.
  - KPI cards: Today's Expenses, This Month Total.
  - Expense list: title, amount, category, payment method, vendor, date.
  - AppBar "Add Expense" button.
- **Actions**:
  - "Add Expense" → `_showAddExpenseDialog`: title, amount, category dropdown, payment method dropdown, vendor, notes.
  - Delete icon per expense → showConfirmDialog → `provider.deleteExpense(id)`.
  - "Custom" period → `showDateRangePicker`.
- **Exits**: Back to shell.
- **State consumed**: `PosProvider` — `expenses`, `canManage`, `addExpense()`, `deleteExpense()`.

---

#### `CustomerScreen`

- **Purpose**: Customer directory with credit management.
- **Entered from**: Shell → Customers tab.
- **UI sections**:
  - Search bar (name/phone).
  - Customer list: name, phone, outstanding balance.
  - AppBar "Add Customer" button.
- **Actions**:
  - "Add Customer" → `_showAddCustomerDialog`: name, phone (required), email (optional), address (optional).
  - Tap customer → bottom sheet with:
    - "Book credit sale" → `_showCreditDialog(kind: 'sale')`: amount + reason → `provider.bookCustomerCredit(...)`.
    - "Settle outstanding" (if balance > 0) → `_showCreditDialog(kind: 'settlement')`: amount + reason → `provider.bookCustomerCredit(...)`.
    - "Credit history" → `_showCreditLogDialog`: FutureBuilder fetching `provider.fetchCreditLog(customerId)`.
- **Exits**: Back to shell.
- **State consumed**: `PosProvider` — `customers`, `bookCustomerCredit()`, `fetchCreditLog()`.

---

#### `TransactionsScreen`

- **Purpose**: Transaction history with search, period filter, payment mode filter.
- **Entered from**: Shell → Transactions tab.
- **UI sections**:
  - Search bar (invoice/order/customer).
  - Period filter: Today / 7D / 30D / All / Custom.
  - Payment mode filter: All / Cash / UPI / Card.
  - Transaction list: invoice number, customer/table, total, payment mode, date, status.
- **Actions**:
  - "Print" button → `provider.printBill(order)` (checks `settings.allowReprint`).
  - "Refund" button → `RefundDialog.show(context, order)`.
  - "View Bill" → `PaymentSuccessScreen` (push with order data).
  - Pull-to-refresh → `provider.triggerSync()`.
  - "Custom" → `showDateRangePicker`.
- **Modals opened**: `RefundDialog`.
- **Exits**: → `PaymentSuccessScreen`.
- **State consumed**: `PosProvider` — `orders`, `settings`, `triggerSync()`, `printBill()`.

---

#### `PrinterStatusScreen`

- **Purpose**: Printer connection status and test page.
- **Entered from**: SettingsScreen "Printer Status".
- **UI sections**:
  - Printer name, connection type (network host:port).
  - Connection status indicator (connected/disconnected).
  - "Print test page" button.
  - Note: Bluetooth printers on roadmap.
- **Actions**:
  - "Print test page" → `provider.printTestPage()`.
- **Exits**: Pop back to SettingsScreen.
- **State consumed**: `PosProvider` — `settings.printer`, `printTestPage()`.

---

### 6.7 More Hub

---

#### `MoreHubScreen`

- **Purpose**: Secondary operations hub — staff profile banner (name, role, outlet, terminal) with a lock/logout action, then role-filtered tiles.
- **Entered from**: Shell → More tab.
- **Tiles filtered by role**:
  - Admin/Manager/Cashier: Shift Dashboard & Cash, Kitchen Display (KDS), Past Transactions & Invoices, Expense Management, Cash Drawer Ledger, Customer Directory, Inventory & Suppliers, Customer Menu QR, Printer Status & Test.
  - Waiter: Past Transactions & Invoices, Customer Directory, Customer Menu QR only — money actions inside stay gated (no refunds, no credit book/settle).
  - Admin only: Reports & Analytics.
  - Admin/Manager: Staff Attendance, Menu Management, Staff Management, POS Configuration & Settings.
  - Staff not bound to a single outlet: Switch outlet tile.
- **Exits**: → the tapped tile's screen, `SelectOutletScreen`, or `PinLoginScreen` on lock.
- **State consumed**: `PosProvider` — `currentStaff.role`, `currentStaff.outletId`, `currentOutlet`.

---

#### `AttendanceScreen`

- **Purpose**: Staff attendance board — clock-in/out tracking.
- **Entered from**: MoreHubScreen "Attendance".
- **UI sections**:
  - "On duty now" section: staff currently clocked in, with clock-in time and minutes worked.
  - "Full log" section: staff clocked out, with total time.
- **Actions**:
  - Pull-to-refresh → `provider.fetchAttendance()`.
  - Auto-fetches on init.
- **Exits**: Pop back to MoreHubScreen.
- **State consumed**: `PosProvider` — `attendanceRecords`, `fetchAttendance()`.

---

#### `CustomerMenuQrScreen`

- **Purpose**: Display QR code for public digital menu page.
- **Entered from**: MoreHubScreen "Customer Menu QR".
- **UI sections**:
  - QR code image encoding `{apiBaseUrl}/m/{outletId}`.
  - URL text display.
  - "Copy link" button.
- **Actions**:
  - "Copy link" → `Clipboard.setData(url)` → SnackBar confirmation.
- **Exits**: Pop back to MoreHubScreen.
- **State consumed**: `PosProvider` — `outlet.id`, `apiBaseUrl`.

---

## 7. Flows — Modal Dialogs

---

### M1. `ManagerPinDialog`

- **Opened from**: `ApplyDiscountDialog` (high discount), `CancelItemDialog` (always), `RefundDialog` (always), `StaffAdminScreen` (non-owner PIN reset).
- **Inputs**: 4–6 digit PIN via numeric keypad, auto-submit at 6 digits or 900 ms after 4th digit.
- **Primary actions**:
  - PIN verified → `provider.verifyManagerPin(pin)` → pops with PIN string (return value).
  - Invalid PIN → error message "Invalid Manager PIN. Try again.", clears input.
  - Close button → pops with `null`.
- **Return value**: `String?` — the verified PIN on success, `null` on cancel.
- **State consumed**: `PosProvider` — `verifyManagerPin()`.

---

### M2. `GuestDetailsDialog`

- **Opened from**: TableSelectionScreen (tap available table).
- **Inputs**:
  - Guest count (stepper + dropdown, 1–20+).
  - Customer name (optional).
  - Phone (optional).
  - Waiter selection (ChoiceChips; searchable list if >4 waiters).
  - Special request note (optional).
  - "Choose existing customer" → sub-dialog with customer search list.
- **Primary actions**:
  - "Start order" → validates phone → `provider.setGuestDetails(...)` + `provider.setOrderNote(...)` → pops → `onStartOrder()` callback fires.
  - "Skip" → pops → `onStartOrder()` callback fires (no guest details set).
- **Return value**: None (callback-based via `onStartOrder`).
- **State consumed**: `PosProvider` — `setGuestDetails()`, `setOrderNote()`, `waiters`, `customers`.

---

### M3. `VariantAndModifiersDialog`

- **Opened from**: PosMenuScreen (tap menu item with variants or modifiers).
- **Inputs**:
  - Variant selection (radio-style, if item `hasVariants`): e.g., Regular/Medium/Large with price.
  - Modifier groups: single-select (radio) or multi-select (checkbox) per group, each option with price.
  - Cooking instructions (free text).
  - Quantity stepper (default 1).
  - Computed unit price and total price displayed live.
- **Primary actions**:
  - "Add to Order" → validates required modifier groups → calls `onConfirm(variant, modifiers, note, quantity)` callback → pops.
  - Required group not selected → SnackBar "Please choose: {group names}".
  - Close button → pops without adding.
- **Return value**: None (callback-based via `onConfirm`).
- **State consumed**: `MenuItem` data (variants, modifierGroups).

---

### M4. `KotPreviewDialog`

- **Opened from**: CartViewScreen "Send KOT" button.
- **Inputs**: Read-only preview.
  - Unsent items list: name, qty, veg mark, modifiers, notes.
  - Order note displayed.
- **Primary actions**:
  - "Send to Kitchen" → pops → `onSendKOT()` callback fires.
  - "Back to Cart" → pops (no action).
- **Return value**: None (callback-based via `onSendKOT`).
- **State consumed**: `PosProvider` — `cart` (unsent items).

---

### M5. `KotSentDialog`

- **Opened from**: After KOT successfully sent (triggered by cart_view logic).
- **Inputs**: Read-only display.
  - KOT number, table, item count.
  - Live lookup of ticket from provider.
- **Primary actions**:
  - "Add More" → pops → `onAddMoreItems()` callback.
  - "View Order" → pops → `onViewOrder()` callback.
  - "Floor Tables" → pops → `onGoToTables()` callback.
  - Not barrier-dismissible.
- **Return value**: None (callback-based).
- **State consumed**: `PosProvider` — `kitchenTickets` (live lookup).

---

### M6. `AddChargeDialog`

- **Opened from**: PaymentScreen "Charges" button.
- **Inputs**:
  - Service charge (₹, numeric).
  - Packaging charge (₹, numeric).
  - Pre-filled from active order's existing charges.
- **Primary actions**:
  - "Update Charges" → confirm dialog → `provider.addCharges(serviceCharge, packaging)` → pops.
  - Close/Cancel → pops without changes.
- **Return value**: None (mutates provider state directly).
- **State consumed**: `PosProvider` — `activeOrder`, `addCharges()`.

---

### M7. `ApplyDiscountDialog`

- **Opened from**: PaymentScreen "Discount" button.
- **Inputs**:
  - Toggle: percentage or fixed amount.
  - Value (numeric).
  - Reason dropdown: Customer Loyalty / Promotional Campaign / Manager Courtesy / Staff Discount / Delay in Service.
- **Primary actions**:
  - "Apply" → if high discount (>20% or >₹500) → `ManagerPinDialog.show()` → on PIN success → `provider.applyDiscount(percent/amount, reason, managerPin)` → pops.
  - "Remove Discount" → `provider.applyDiscount(percent:0, amount:0, reason:null)` → pops.
  - Manager PIN cancelled → stays on dialog.
- **Return value**: None (mutates provider state directly).
- **State consumed**: `PosProvider` — `activeOrder`, `applyDiscount()`.

---

### M8. `CancelItemDialog`

- **Opened from**: RunningOrderDetailScreen (cancel item icon on an order item).
- **Inputs**:
  - Reason selection: Wrong Item Ordered / Customer Cancelled / Kitchen Delayed / Duplicate Item / Quality Complaint / Other (custom text field).
- **Primary actions**:
  - "Confirm Cancel" → `ManagerPinDialog.show()` (always required) → on PIN success → calls `onConfirmCancel(reason, managerPin)` callback → pops.
  - Manager PIN cancelled → stays on dialog.
- **Return value**: None (callback-based via `onConfirmCancel`).
- **State consumed**: None directly (delegates to callback).

---

### M9. `CashInOutDialog`

- **Opened from**: ShiftDashboardScreen "Cash In"/"Cash Out", CashDrawerScreen "Cash In"/"Cash Out".
- **Inputs**:
  - Amount (numeric).
  - Reason chips:
    - Cash In: Opening Float Top-up / Change Replenishment / Owner Deposit / Other Inflow.
    - Cash Out: Petty Cash Expense / Supplier Payout / Bank Deposit / Staff Advance / Emergency Payout.
  - Date/time picker.
  - Reference note (optional).
- **Primary actions**:
  - Cash In: "Add Cash to Drawer" → validates → `provider.addCashIn(amount, reason, date, ref)` → pops.
  - Cash Out: "Remove Cash from Drawer" → validates against drawer balance → `provider.addCashOut(amount, reason, date, ref)` → pops.
  - Cash Out exceeding drawer balance → error SnackBar.
- **Return value**: None (mutates provider state directly).
- **State consumed**: `PosProvider` — `currentShift`, `drawerBalance`, `addCashIn()`, `addCashOut()`.

---

### M10. `MergeTablesDialog`

- **Opened from**: TableSelectionScreen (merge action on occupied table).
- **Inputs**:
  - Checkbox list of eligible tables (excludes primary table and tables merged to other primaries).
  - Already-merged tables shown as pre-checked.
- **Primary actions**:
  - "Merge Tables" → confirm dialog → `provider.mergeTables(primaryId, secondaryId)` for each selected → pops → SnackBar confirmation.
  - Uncheck an already-merged table → confirm "Split table?" dialog → `provider.unmergeTable(id)` immediately.
  - "Cancel" → pops.
- **Return value**: None (mutates provider state directly).
- **State consumed**: `PosProvider` — `tables`, `mergeTables()`, `unmergeTable()`.

---

### M11. `MoveTableDialog`

- **Opened from**: TableSelectionScreen (move action on occupied table).
- **Inputs**:
  - ChoiceChip list of available destination tables (status == available, excludes source table).
  - Displays order reference (order number or table number).
- **Primary actions**:
  - "Move to {table}" → confirm dialog → `provider.moveTable(fromId, toId)` → pops → SnackBar confirmation.
  - No available tables → "No available tables on floor!" message.
  - "Cancel"/Close → pops.
- **Return value**: None (mutates provider state directly).
- **State consumed**: `PosProvider` — `tables`, `orders`, `moveTable()`.

---

### M12. `OfflineSyncDialog`

- **Opened from**: MoreHubScreen "Sync Status", SettingsScreen sync indicator, MainAdaptiveShell sync indicator.
- **Inputs**: Read-only status display.
  - Headline: "Offline" / "Sync paused" / "Syncing..." / "All changes synced" with color-coded icon.
  - Server connectivity status.
  - Live updates status.
  - Pending sync count.
  - Last sync timestamp.
  - Blocked reason (if any) with explanation.
  - Offline notice (if offline with pending changes).
  - Server rejections list with "Clear" button.
- **Primary actions**:
  - "Sync now" → `provider.triggerSync()` → SnackBar result ("All changes are synced" / "Server not reachable..." / "{N} change(s) still waiting").
  - "Clear" (on rejections) → `provider.clearSyncRejections()`.
  - Close → pops.
- **Return value**: None.
- **State consumed**: `PosProvider` — `isOfflineMode`, `pendingSyncCount`, `syncBlockedReason`, `syncRejections`, `lastSyncAt`, `realtimeConnected`, `triggerSync()`, `clearSyncRejections()`.

---

### M13. `PrinterErrorDialog`

- **Opened from**: PaymentScreen (print fail), CartViewScreen (KOT print fail).
- **Inputs**: Read-only display.
  - Printer name (default: "Kitchen Thermal Printer (TVS RP3200)").
  - Error icon and message: "Unable to communicate with {printerName}. Check cables, paper roll, or network connection."
- **Primary actions**:
  - "Retry Print" → pops → `onRetry()` callback.
  - "Skip Print" → pops → `onContinue()` callback.
- **Return value**: None (callback-based).
- **State consumed**: None directly.

---

### M14. `RefundDialog`

- **Opened from**: TransactionsScreen "Refund" button.
- **Inputs**:
  - Full Refund / Partial Refund toggle (ChoiceChips).
  - Refund amount (₹, pre-filled with refundable amount for full; editable for partial).
  - Reason chips: Customer Dissatisfaction / Wrong Billing / Overcharged / Food Quality Issue / Order Cancelled After Payment / Other.
  - Refund mode: Cash / UPI / Original Method.
  - Refundable = grand total minus already-refunded amount.
- **Primary actions**:
  - "Confirm Refund" → `ManagerPinDialog.show(title: 'Refund Authorization')` → on PIN success → validates amount → `provider.processRefund(orderId, amount, reason, isFullRefund, refundMode, managerPin)` → pops → SnackBar (success or failure).
  - Manager PIN cancelled → stays on dialog.
  - Invalid amount → error SnackBar.
- **Return value**: None (mutates provider state directly).
- **State consumed**: `PosProvider` — `processRefund()`, order data.

---

## 8. State / Provider Summary

All screens consume a single `PosProvider` (ChangeNotifier) registered via `MultiProvider` in `main.dart`. Key provider properties and methods used across the app:

### Properties
- `ready`, `needsOrgSetup`, `hasOpenShift`, `isOfflineMode`
- `currentStaff`, `activeStaff`, `staff` (list)
- `outlets`, `outlet` (current)
- `tables`, `floors`, `orders`, `activeOrder`, `cart`
- `menuItems`, `customers`, `expenses`, `inventoryItems`, `suppliers`, `purchases`, `stockLog`
- `currentShift`, `shiftStats`, `cashMovements`, `drawerBalance`
- `settings`, `subscription`
- `kitchenTickets`, `readyOrders`, `attendanceRecords`
- `pendingSyncCount`, `syncBlockedReason`, `syncRejections`, `lastSyncAt`, `realtimeConnected`
- `serverRangeReport`, `canManage`

### Methods
- Auth: `verifyPin()`, `loginStaff()`, `registerOrg()`, `linkTerminal()`, `selectOutlet()`, `verifyManagerPin()`
- Shift: `openShift()`, `closeShift()`, `addCashIn()`, `addCashOut()`
- Orders: `setGuestDetails()`, `setOrderNote()`, `updateCartQty()`, `holdOrder()`, `sendKOT()`, `processPayment()`, `cancelItem()`, `markServed()`, `advanceKotStatus()`
- Menu: `addMenuItem()`, `updateMenuItem()`, `deleteMenuItem()`, `toggleAvailability()`
- Staff: `addStaff()`, `updateStaff()`, `toggleStaffActive()`, `resetStaffPin()`, `changeStaffRole()`
- Settings: `updateSettings()`, `addCharges()`, `applyDiscount()`
- Tables: `mergeTables()`, `unmergeTable()`, `moveTable()`
- Inventory: `adjustStock()`, `addSupplier()`, `recordPurchase()`, `markPurchasePaid()`, `paySupplier()`
- Expenses: `addExpense()`, `deleteExpense()`
- Customers: `bookCustomerCredit()`, `fetchCreditLog()`
- Reports: `fetchServerReport()`
- Sync: `triggerSync()`, `clearSyncRejections()`
- Printing: `printReceipt()`, `printBill()`, `printKOT()`, `printTestPage()`
- Refund: `processRefund()`
- Subscription: `enableAutoRenew()`, `payOneCycle()`, `cancelAutoRenew()`
- Attendance: `fetchAttendance()`
