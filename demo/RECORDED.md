# Recorded demo coverage — 10 October 2026

Pixel 6 API 36 emulator, portrait 1080 × 2400, debug build of `main` (commit `ab5555b`) talking to a local backend with the demo seed (org code `HISHOBKR`, Baner Outlet). Clips are silent. Every order, payment and report shown went through the real server. Idle stretches longer than 3 s are cut to 2.5 s; the last screen holds for 3 s.

Outlet settings at recording time: restaurant name "Green Candle - Baner Outlet", GST 0%, ₹25 takeaway packaging, UPI ID `demo@upi` (a placeholder, not a real payee). Address, GSTIN and FSSAI are still the seed's demo values.

| File | Role | Content |
|---|---|---|
| recordings/01-waiter.mp4 | Waiter (Amit, PIN 1111) | PIN login → floor plan → T05, 3 guests → Dal Makhani + 2 Butter Naan → KOT #1203 → order details (no Checkout for waiters) → T05 occupied, ₹340. |
| recordings/02-kitchen.mp4 | Kitchen (Chef Sharma, PIN 5555) | KDS New/Preparing/Ready/Served → start T05 and T01 → mark T05 ready ("notifies the floor") → lock. No "served" button for the kitchen. |
| recordings/03-manager.mp4 | Manager (Neha, PIN 8888) | Running orders → T03 bill ₹740 → 10% Customer Loyalty discount → ₹666 → ₹1,000 cash, ₹334 change → Green Candle receipt INV-1050 → shift dashboard (drawer ₹3,532) → staff management actions → sections & tables. |
| recordings/04-cashier-takeaway-upi.mp4 | Cashier (Rahul, PIN 1234) | Takeaway: Paneer Tikka with Medium Spicy + Laccha Onions, Butter Chicken → KOT #1205 → bill ₹670 incl. ₹25 packaging → UPI QR "Green Candle · demo@upi" → paid → receipt INV-1049 listing the add-ons. |
| recordings/05-cashier-cash-in.mp4 | Cashier | Shift dashboard → Cash In ₹500 (Change Replenishment) → drawer ₹2,866 → transactions filtered to UPI. |
| recordings/06-admin.mp4 | Admin/owner (Vikram, PIN 2468) | Home dashboard KPIs → reports (today: 6 orders, ₹2,872; order type, payment mode, top items, staff performance; 7-day view) → POS settings with the UPI QR. |

`recordings/raw-2026-10-10/` holds the untrimmed takes, including earlier manager/admin takes that still show the seed name "Spice Haven".

`recordings/old-2026-10-09/` holds the 9 October set, recorded with the isolated `tool/demo_main.dart` build (fictional in-memory data, no server). It is kept for reference only:

- it shows behaviour since fixed or removed ("Change to return -₹0", the offline sync/"Simulate Offline" dialog, "Invoice: pending sync", `demo@invalid` UPI);
- `01-sales-demo` stops on the KOT-sent dialog and never reaches payment;
- `13-cash-and-shift-close` stops on an unsubmitted Cash Out dialog and never closes the shift;
- `waiter_role_demo-other-session.mp4` is mostly the Android home screen and never logs in.

`recordings/receipt.png` is a still from that old set.

SCENARIOS.md lists further shooting scripts that are not recorded.
