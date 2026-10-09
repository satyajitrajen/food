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
    title: 'Fast Table-to-Bill Flow',
    desc: 'Section, table, order, KOT, and settle in a few taps, so the whole loop fits the short window a waiter has during peak service.',
  },
  {
    icon: <Database size={22} />,
    title: 'Offline-First Durability',
    desc: 'Orders and payments write to a local cache and sync when the network returns. A dead router never stops a live dinner service.',
  },
  {
    icon: <ChefHat size={22} />,
    title: 'Live Kitchen Display',
    desc: 'No more lost paper KOT slips. Chefs work a New → Preparing → Ready flow and the floor is notified when food is ready.',
  },
  {
    icon: <ShieldCheck size={22} />,
    title: 'Blind Cash Counts',
    desc: 'Blind denomination counts at shift close, cash-in/out logs, and Z-reports make unrecorded payouts and register shortages visible.',
  },
  {
    icon: <Rocket size={22} />,
    title: 'Multi-Outlet SaaS',
    desc: 'One owner console across up to 5 outlets, with per-outlet staff, menus, and reports.',
  },
];

const TAGS = [
  'Configurable GST',
  'WhatsApp Bills',
  '4–6 Digit Staff PINs',
  'Split Tender',
  'Takeaway & Delivery',
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
            Hishobkr treats a restaurant like the high-pressure machine it is. Every screen
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
