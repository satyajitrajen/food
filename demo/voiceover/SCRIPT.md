# Voice-over script

Record one take per video while watching its silent version in
`demo/recordings/final/` (start recording at 0:00). Save it as
`demo/voiceover/<video name>.wav` (or .m4a / .mp3), e.g. `01-waiter.wav`,
then run `python demo/build_videos.py` again to mix it in.

Each line starts at its timecode; the budget is how many words fit
before the next line at a relaxed pace (~2.6 words/s). Running a
little long is fine. The full demo (`00-full-demo.mp4`) reuses these takes.

Full demo only (`00-intro.wav`, over the opening card):
> Hishobkr is a restaurant POS for the whole team. Let's follow one day, from the waiter's order to the owner's report.

## 01-waiter.mp4 — Waiter (0:48.6)

| Time | Words | Say |
|---|---|---|
| 0:00.0 | 10 | This is Hishobkr for the waiter. |
| 0:04.0 | 30 | Every staff member has their own profile. Amit picks his name and signs in with his four-digit PIN. |
| 0:15.9 | 6 | He seats the guests at table five. |
| 0:18.4 | 17 | Then he adds dishes from the menu: one Dal Makhani and two Butter Naan. |
| 0:25.1 | 21 | He checks the kitchen ticket and sends it. The kitchen screen gets it right away. |
| 0:33.4 | 14 | The order is saved. Waiters take orders; billing stays with the cashier. |
| 0:39.1 | 24 | Back on the floor plan, table five now shows as occupied. |
| 0:45.1 | end card | (Hishobkr. One POS for every role. — optional) |

## 02-kitchen.mp4 — Kitchen (0:46.6)

| Time | Words | Say |
|---|---|---|
| 0:00.0 | 10 | Now the kitchen. |
| 0:04.0 | 22 | The chef signs in on the kitchen screen with his own PIN. |
| 0:12.7 | 7 | New tickets appear instantly. |
| 0:15.7 | 19 | Table five's order is here. One tap, and it moves to Preparing. |
| 0:23.1 | 42 | When it's cooked, the chef marks it ready, and the waiter is notified on the floor. |
| 0:39.6 | 18 | The kitchen sees tickets only. No bills, no payments. |
| 0:43.1 | end card | (Hishobkr. One POS for every role. — optional) |

## 03-manager.mp4 — Manager (1:10.2)

| Time | Words | Say |
|---|---|---|
| 0:00.0 | 10 | Next, the manager. |
| 0:04.0 | 18 | Neha, the manager, signs in with her PIN. |
| 0:11.1 | 6 | She sees every running order. |
| 0:13.6 | 15 | She opens table three's bill: five items, seven hundred and forty rupees. |
| 0:19.7 | 18 | She gives a ten percent loyalty discount. Bigger discounts need a manager's approval. |
| 0:27.0 | 15 | The customer pays a thousand in cash, and the change is worked out for her. |
| 0:33.0 | 28 | The receipt has its invoice number from the server, and can be printed, sent on WhatsApp, or shared as a PDF. |
| 0:44.1 | 25 | The shift dashboard shows how much cash should be in the drawer, updated with every sale. |
| 0:54.0 | 23 | In staff management she can change roles, reset PINs, or deactivate staff. |
| 1:03.2 | 18 | And set up the outlet's sections and tables. |
| 1:06.7 | end card | (Hishobkr. One POS for every role. — optional) |

## 04-cashier-takeaway-upi.mp4 — Cashier: takeaway & UPI (0:54.0)

| Time | Words | Say |
|---|---|---|
| 0:00.0 | 10 | Now the cashier, with a takeaway order. |
| 0:04.0 | 17 | Rahul, the cashier, starts a takeaway order. |
| 0:10.9 | 28 | Paneer Tikka can be customised. He picks medium spicy and adds Laccha Onions for fifteen rupees, then adds Butter Chicken. |
| 0:21.9 | 27 | Both dishes go to the kitchen in a single ticket. |
| 0:32.3 | 14 | For takeaway, the packaging charge is added automatically. |
| 0:38.0 | 15 | The customer pays by UPI. The QR already has the exact amount. |
| 0:44.0 | 26 | The receipt lists every add-on, so the bill is clear. |
| 0:50.5 | end card | (Hishobkr. One POS for every role. — optional) |

## 05-cashier-cash-in.mp4 — Cashier: cash drawer (0:45.3)

| Time | Words | Say |
|---|---|---|
| 0:00.0 | 10 | The cashier also looks after the cash drawer. |
| 0:04.0 | 21 | After a sale, the cashier can start the next order, or check the cash drawer. |
| 0:12.4 | 7 | The shift dashboard shows every sale. |
| 0:15.3 | 26 | When cash is added to the drawer, he records it with a reason. Here, five hundred rupees for change. |
| 0:25.6 | 13 | The expected cash in the drawer updates straight away. |
| 0:30.6 | 38 | And any bill can be found in transactions, filtered by cash, UPI or card. |
| 0:41.8 | end card | (Hishobkr. One POS for every role. — optional) |

## 06-admin.mp4 — Owner (0:59.1)

| Time | Words | Say |
|---|---|---|
| 0:00.0 | 10 | Finally, the owner's view. |
| 0:04.0 | 16 | Vikram, the owner, signs in as admin. |
| 0:10.5 | 17 | His home screen shows today's sales, orders, cash in the drawer and open tickets. |
| 0:17.1 | 14 | Every part of the restaurant is one tap away. |
| 0:22.5 | 17 | Reports show today's six orders, the profit, order types and payment modes. |
| 0:29.4 | 41 | He sees the best-selling dishes and what each staff member sold, for today, the last seven days, or any dates. |
| 0:45.5 | 15 | In settings he manages the restaurant profile, subscription and taxes. |
| 0:51.3 | 20 | And sets the UPI ID once, for every bill. |
| 0:55.6 | end card | (Hishobkr. One POS for every role. — optional) |
