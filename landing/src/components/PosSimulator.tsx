import React from 'react';
import { Zap, Database, ChefHat, ShieldCheck, Rocket } from 'lucide-react';

const ECOSYSTEM_PILLARS = [
  { icon: <Zap size={16} />, label: '90s Counter Billing' },
  { icon: <Database size={16} />, label: '100% Offline Durability' },
  { icon: <ChefHat size={16} />, label: 'Live Kitchen Display (KDS)' },
  { icon: <ShieldCheck size={16} />, label: 'Theft-Proof Cash Counts' },
  { icon: <Rocket size={16} />, label: 'Multi-Outlet Cloud Console' },
];

export const PosSimulator: React.FC = () => {
  return (
    <section id="simulator" className="t-ecosystem-section">
      <div className="t-container">
        <div className="t-ecosystem-head">
          <span className="t-eyebrow">Hardware &amp; Software In Sync</span>
          <h2 className="t-section-title">One Unified System Across Every Counter, Kitchen &amp; Outlet</h2>
          <p className="t-section-desc">
            FoodPOS orchestrates order punching, offline local caching, digital kitchen tickets, cash drawer balances, and branch-wide reporting in a single high-speed loop.
          </p>
        </div>

        <div className="t-ecosystem-card">
          <img
            src="/images/benefits-composite.png"
            alt="FoodPOS complete restaurant operations ecosystem: 90s billing terminal, offline cache cloud, live kitchen display, theft-proof cash count, and multi-outlet console"
            className="t-ecosystem-img"
            loading="lazy"
          />

          <div className="t-ecosystem-pillars">
            {ECOSYSTEM_PILLARS.map((p) => (
              <div className="t-ecosystem-pill" key={p.label}>
                {p.icon}
                <span>{p.label}</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
};
