export interface FAQItem {
  id: string;
  question: string;
  answer: string;
}

export const FAQS: FAQItem[] = [
  {
    id: 'faq-1',
    question: 'How does FoodPOS work when our restaurant internet goes completely down?',
    answer: 'FoodPOS is built from the ground up as an offline-first system. All terminal operations — table orders, menu lookups, modifier selections, and bill settlements — run against a high-speed local device cache. Outbox transactions are queued and cryptographically persisted locally. Once Wi-Fi reconnects, FoodPOS automatically syncs transactions to your cloud database with timestamp integrity, guaranteeing zero lost orders or double bills.',
  },
  {
    id: 'faq-2',
    question: 'Does FoodPOS calculate Indian GST (CGST & SGST) accurately?',
    answer: 'Yes. FoodPOS provides compliant integer-paise tax math. It computes 5% restaurant GST (2.5% CGST + 2.5% SGST) over the taxable subtotal (net of discounts plus service charges, conforming to Indian F&B tax standards). It also supports composite tax schemes, alcohol tax slabs, and inclusive vs exclusive item pricing.',
  },
  {
    id: 'faq-3',
    question: 'Can our captains and waitstaff use standard Android tablets or phones for table ordering?',
    answer: 'Yes! FoodPOS runs natively on Android tablets, desktop PCs (Windows & Linux), and browser-based terminals. Waiters can carry lightweight 8-inch or 10-inch Android tablets directly to tables to punch orders and fire KOTs in real-time.',
  },
  {
    id: 'faq-4',
    question: 'How does the Kitchen Display System (KDS) replace printed paper KOTs?',
    answer: 'FoodPOS includes a dedicated display-only Kitchen role (Chef station). Chefs view live order tickets color-coded by waiting time and advance them through an immutable status state machine: New → Preparing → Ready → Served. This eliminates lost paper slips, kitchen confusion, and costly printer ink roll replacements.',
  },
  {
    id: 'faq-5',
    question: 'Which thermal printers and cash drawers are supported?',
    answer: 'FoodPOS supports industry-standard 2-inch (58mm) and 3-inch (80mm) ESC/POS thermal receipt printers over USB, Bluetooth, and LAN/Wi-Fi (including brands like Epson, TVS, NGX, Everycom, and Posiflex). It also sends kick-signals to RJ11 cash drawers upon bill settlement.',
  },
  {
    id: 'faq-6',
    question: 'How does shift closing prevent cash leaks and register shortages?',
    answer: 'Cashiers perform a blind cash count at the end of each shift, entering physical currency denominations. FoodPOS cross-references this count against opening cash, cash sales, paid-in/paid-out entries, cash refunds, and petty cash expenses. It generates an instant Z-Report highlighting any variance, with an operational benchmark of keeping discrepancy within ±₹50.',
  },
];
