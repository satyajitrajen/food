export interface FAQItem {
  id: string;
  question: string;
  answer: string;
}

export const FAQS: FAQItem[] = [
  {
    id: 'faq-1',
    question: 'How does Hishobkr work when our restaurant internet goes down?',
    answer: 'Hishobkr is offline-first. Table orders, menu lookups, KOTs, and bill settlements run against data stored on the device, and every change is queued in a local outbox. When the connection returns, the queue syncs to the cloud automatically using idempotent requests, so an order is never recorded twice.',
  },
  {
    id: 'faq-2',
    question: 'How does Hishobkr handle GST (CGST & SGST)?',
    answer: 'GST is configurable per outlet: set your GST rate and choose whether menu prices are tax-inclusive or tax-exclusive. Hishobkr splits the tax into CGST and SGST, computes it with integer-paise math, and prints your GSTIN on every GST invoice.',
  },
  {
    id: 'faq-3',
    question: 'Can our captains and waiters use Android tablets or phones for table ordering?',
    answer: 'Yes. Hishobkr runs on Android tablets and phones, on Windows desktops, and in the browser. Waiters can take orders at the table and fire KOTs straight to the kitchen display. Each staff member signs in with their own 4–6 digit PIN.',
  },
  {
    id: 'faq-4',
    question: 'How does the Kitchen Display replace printed paper KOTs?',
    answer: 'Hishobkr includes a display-only Kitchen role. KOTs appear on the kitchen screen as soon as they are fired, and chefs move each ticket from New to Preparing to Ready. Marking a ticket Ready notifies the floor, and the waiter marks it Served.',
  },
  {
    id: 'faq-5',
    question: 'Which receipt printers are supported?',
    answer: 'Hishobkr prints to ESC/POS thermal receipt printers (80 mm) connected over your local network (LAN or Wi-Fi). You can also share bills to guests on WhatsApp instead of printing.',
  },
  {
    id: 'faq-6',
    question: 'Does Hishobkr support takeaway, delivery, and split payments?',
    answer: 'Yes. Besides dine-in tables, you can punch takeaway and delivery orders, and settle any bill across more than one payment mode, for example part cash and part UPI.',
  },
  {
    id: 'faq-7',
    question: 'How does shift closing catch cash shortages?',
    answer: 'At the end of a shift the cashier does a blind cash count, entering the physical notes and coins without seeing the expected total. Hishobkr compares the count against opening cash, cash sales, paid-in/paid-out entries, and cash refunds, and the Z-report shows any variance.',
  },
  {
    id: 'faq-8',
    question: 'What does the plan include?',
    answer: 'One plan at ₹1,999 per year: up to 5 outlets and 20 staff members, with a 7-day free trial. Start the trial from the owner console; you can enable auto-renew by UPI or card at any time.',
  },
];
