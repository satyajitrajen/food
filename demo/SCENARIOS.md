# Hishobkr demo shooting scripts

Record portrait clips with a two-second pause at each result. Use fictional guests and amounts; no real payments. Clips are silent: narration below is a voiceover script. Restart the isolated demo between independent takes. Every demo role uses PIN 1234.

## Setup and recording

`flutter run -d emulator-5554 -t tool/demo_main.dart`

In another terminal: `./tool/record-demo.ps1 -Scene 01-login -Seconds 60`. Android recordings are limited to 180 seconds per clip. The fixture entry point uses existing screens and an in-memory provider with no backend connection. It replaces the installed emulator build; restore the normal app with `flutter run -d emulator-5554`. Keep each clip below three minutes.

## Core sales story (record in this order)

| Clip | Actions | Voiceover | Result to hold on screen |
|---|---|---|---|
| 01 Login and shift | Select Demo admin; enter 1234; enter opening float 1000; start shift and confirm. | “Staff sign in with their own PIN and open the register with a counted float.” | Home with active shift. |
| 02 Dine-in | Open Tables; select T1; enter guest count if prompted; add Paneer Tikka, Veg Biryani and Fresh Lime Soda; show customization; confirm; open cart. | “Build a table order with quantities and preparation notes.” | Three-item cart and bill total. |
| 03 Kitchen handoff | Send KOT; dismiss confirmation; open More → Kitchen Display; show ticket; advance its available status controls to ready; return to running order. | “The kitchen tracks preparation, and the front desk sees what is ready.” | Ready ticket/order. Local fixture demonstrates UI only. |
| 04 Bill and cash | Open the order’s payment screen; expand items; show discount and charges; cancel those dialogs for the baseline take; choose Cash; enter sufficient cash; collect. | “Review the complete bill and collect cash with the change calculated.” | Payment success, tender and receipt. |
| 05 Takeaway | Start a Takeaway order from Home; add one biryani; show packaging charge if configured; settle by Card with a fictional reference. | “Counter and takeaway sales follow the same billing flow.” | Completed takeaway receipt. |
| 06 Delivery | Start Delivery; add food; enter fictional guest/address details where offered; show delivery charge; settle. | “Track delivery orders and their additional charges.” | Delivery bill. |
| 07 UPI | Create another order; choose UPI; hold on QR if a demo UPI ID is configured; enter a fictional reference; collect only in fixture mode. | “Present a payment QR and record the confirmed UPI payment.” | UPI tender/receipt. No actual transfer. |
| 08 Split tender | Create a bill; choose Split; add Cash and Card parts totaling the due amount; collect. | “One bill can be settled across multiple payment methods.” | Both payment parts. |
| 09 Customer credit | More → Customer Directory; create Demo Guest using fictional contact details; create order; choose Credit and select guest; settle; return to customer ledger; record settlement. | “Keep customer credit and repayments visible in one ledger.” | Credit balance before and after settlement. |

## Operations and management

| Clip | Actions | Voiceover | Result to hold |
|---|---|---|---|
| 10 Running orders | Create two table orders; open Orders; inspect detail; add another item and send a second KOT. | “Reopen live orders and send only the newly added items.” | Updated order and separate KOT. |
| 11 Tables | With occupied T1 and empty T2, open move-table control and move to T2; create another compatible order and use merge controls. | “Move guests and combine tables while keeping their order together.” | Updated table map. |
| 12 Cancellation | Add an unsent item and remove it; then cancel a sent item through its reason/approval flow. | “Corrections to kitchen orders carry a reason and the required authorization.” | Corrected cart/KOT. |
| 13 Transactions and refund | More → Past Transactions; inspect the completed cash sale; open refund; enter a reason and approve a partial refund. | “Find receipts and record refunds against the original payment.” | Refund record and adjusted transaction. |
| 14 Expenses | More → Expense Management; add a fictional petty-cash expense of 100; inspect listing. | “Operating expenses stay linked to the day’s cash records.” | Saved expense. |
| 15 Cash ledger | More → Cash Drawer; add Cash In 200 and Cash Out 50 with reasons; inspect expected balance. | “The drawer accounts for sales, expenses and manual cash movements.” | Ledger entries and expected cash. |
| 16 Inventory | More → Inventory & Suppliers; create a demo ingredient; adjust opening stock with reason; create supplier and record purchase; inspect stock history. | “Track ingredients, supplier purchases and stock movement.” | Purchase and increased stock. |
| 17 Attendance | More → Staff Attendance; inspect the login-created attendance entry; use available clock controls. | “Staff attendance is visible alongside outlet operations.” | Attendance log. |
| 18 Reports | As admin, More → Reports; select date range; inspect sales, tenders and category views. | “Review sales performance and how customers paid.” | Totals matching the demonstrated sales. |
| 19 Menu management | More → Menu Management; create Demo Dessert, price 120; edit price; toggle availability; inspect POS listing. | “Manage categories, prices and availability from the terminal.” | Updated menu. |
| 20 Staff management | More → Staff Management; create a fictional staff account; inspect role, outlet assignment and PIN reset controls. | “Control who can access each outlet and operation.” | Staff list and role. |
| 21 Settings | More → Settings; inspect business profile, tax, dining sections, tables and printer settings; change only fixture values. | “Configure the outlet’s billing and dining setup.” | Settings sections. |
| 22 Roles | Lock; select waiter and sign in; show allowed navigation; repeat for kitchen, cashier and manager. | “Each role gets the tools needed for its responsibilities.” | Different navigation for each role. |
| 23 Close shift | More → Shift Dashboard; close shift; enter counted denominations; review variance and confirm. | “End the day by comparing counted cash against the expected drawer.” | Closed shift summary. Record last. |

## Scenes requiring a dedicated test backend or hardware

These are scripted coverage, not claims that the in-memory demo verifies integrations. Record against a dedicated seeded test tenant, never the production restaurant.

| Clip | Actions | Voiceover | Required evidence |
|---|---|---|---|
| 24 Organization setup | Fresh test terminal: enter test organization code; Continue; select outlet and staff; log in. Separately inspect registration without buying a plan. | “Bind a new terminal to your organization and outlet.” | Server-loaded outlet/staff. |
| 25 Offline recovery | Log in online first; disconnect emulator networking; create order and KOT; inspect queued sync; reconnect; wait for acknowledgements; verify server order once. | “Continue during a connection outage and synchronize when service returns.” | Queue drained and server record without duplicates. |
| 26 Two-terminal KDS | Cashier terminal sends KOT; kitchen terminal receives it; kitchen marks ready; cashier receives ready alert. | “Live kitchen updates connect staff across terminals.” | Both terminal views and received alert. |
| 27 Subscription | Test admin opens Settings subscription card; inspect status; use Razorpay test mode for owner re-auth/checkout if configured; await webhook update. | “Owners can review and renew their subscription.” | Test payment and updated entitlement; no live charge. |
| 28 Printer | Configure an actual test printer; send KOT; print receipt; disconnect and demonstrate visible error/retry. | “Print kitchen tickets and receipts, with connection failures made visible.” | Physical output and recovery. Emulator alone cannot prove this. |
| 29 Sharing | Open receipt PDF/share control; inspect PDF; open share chooser and cancel. | “Share a customer receipt from the completed sale.” | PDF preview. Do not send to a real contact. |
| 30 Customer menu QR | More → Customer Menu QR; display QR; scan with second device against the test backend. | “Guests can scan to browse the live menu.” | Second-device menu; fixture has no public menu server. |
| 31 Outlet switch | On multi-outlet test tenant, sign in as authorized staff; switch outlet; inspect changed catalog and tables; demonstrate restricted staff assignment. | “Keep each outlet’s operations and access separate.” | Correct outlet data and access control. |

## Take acceptance

Reject takes with errors, unfinished loading, accidental personal data or obscured buttons. Verify item quantities, final total, tender, cash change and resulting order status visually. Keep raw MP4s in `demo/recordings/`; maintain actual recorded coverage separately from this complete shooting plan. Empty states are honest demo screens, not proof of populated operations.
