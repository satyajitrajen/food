import React from 'react';
import {
  Database,
  Zap,
  ChefHat,
  ShieldCheck,
  Rocket,
} from 'lucide-react';

const BENEFITS = [
  {
    icon: <Zap size={22} />,
    title: '90-Second Billing',
    desc: 'Section, table, order, KOT, and settle. The whole loop fits inside the 90-second window a waiter has during peak service.',
  },
  {
    icon: <Database size={22} />,
    title: 'Offline-First Durability',
    desc: 'Orders and payments write to a local cache and sync when the network returns. A dead router never stops a live dinner service.',
  },
  {
    icon: <ChefHat size={22} />,
    title: 'Live Kitchen Display',
    desc: 'No more lost paper KOT slips. Chefs work an immutable New → Preparing → Ready flow and the waiters are notified automatically.',
  },
  {
    icon: <ShieldCheck size={22} />,
    title: 'Theft-Proof Cash Counts',
    desc: 'Denomination-level blind counts, cash-in/out logs, and Z-reports make unrecorded payouts and register shortages visible.',
  },
  {
    icon: <Rocket size={22} />,
    title: 'Multi-Outlet SaaS',
    desc: 'One owner console across every branch, with per-outlet staff, menus, and reports, plus your own kitchen branding.',
  },
];

const TAGS = [
  '5% GST Accurate',
  'WhatsApp Bills',
  'UPI & Card Splits',
  'Split Tender',
  'Multi-Outlet',
  'Free Updates',
];

export const BenefitsSection: React.FC = () => {
  return (
    <section id="benefits" className="t-benefits">
      <div className="t-container t-benefits-grid">
        {/* Left: intro + tags */}
        <div className="t-benefits-intro">
          <span className="t-eyebrow">Benefits</span>
          <h2 className="t-benefits-title">
            Unlock a New Era of Restaurant Operations, Even When the Internet Drops
          </h2>
          <p className="t-benefits-desc">
            FoodPOS treats a restaurant like the high-pressure machine it is. Every screen
            is built so a full dining room stays smooth, accurate, and audit-clean from the
            first order to the final Z-report.
          </p>
          <ul className="t-benefit-tags">
            {TAGS.map((tag) => (
              <li key={tag}>{tag}</li>
            ))}
          </ul>
        </div>

        {/* Right: benefit list */}
        <ul className="t-benefit-list">
          {BENEFITS.map((b) => (
            <li className="t-benefit-item" key={b.title}>
              <span className="t-benefit-icon">{b.icon}</span>
              <div>
                <h3>{b.title}</h3>
                <p>{b.desc}</p>
              </div>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
};
