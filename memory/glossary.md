# Glossary

- **KOT** — Kitchen Order Ticket; fire of unsent items to kitchen; FSM new→preparing→ready→served.
- **Z-Report** — End-of-shift reconciliation: sales per tender, refunds, expenses, expected vs counted cash, variance.
- **Outbox** — Local write-ahead queue on the client; entries replayed FIFO with idempotency keys when online.
- **Drawer** — Physical cash balance: opening + cash sales + cash-in − cash expenses − cash-out − cash refunds.
- **Paise** — 1/100 INR; all backend money ints. `26460` = ₹264.60.
- **Manager gate** — Re-PIN prompt guarding privileged actions (refund, big discount, void).
- **Tender** — Payment instrument (cash/upi/card) used for a transaction or refund.
