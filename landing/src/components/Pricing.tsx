import React, { useState } from 'react';
import { Check, Sparkles } from 'lucide-react';

interface PricingProps {
  onOpenDemo: (planName?: string) => void;
}

export const Pricing: React.FC<PricingProps> = ({ onOpenDemo }) => {
  const [isAnnual, setIsAnnual] = useState<boolean>(true);

  return (
    <section id="pricing" className="section">
      <div className="container">
        <div className="section-header">
          <span className="section-eyebrow">Fair, Transparent Pricing</span>
          <h2 className="section-title">Plans Built for Single Cafés to Multi-Floor Restaurants</h2>
          <p className="section-desc">
            No hidden transaction commissions. 100% of your earnings stay with you.
          </p>
        </div>

        {/* Monthly vs Annual Billing Toggle */}
        <div className="pricing-toggle-wrap">
          <span style={{ color: !isAnnual ? 'var(--text-espresso)' : 'var(--text-muted)' }}>Monthly</span>
          <div className="toggle-pill">
            <button
              className={`toggle-btn ${!isAnnual ? 'active' : ''}`}
              onClick={() => setIsAnnual(false)}
            >
              Monthly
            </button>
            <button
              className={`toggle-btn ${isAnnual ? 'active' : ''}`}
              onClick={() => setIsAnnual(true)}
            >
              Annual
            </button>
          </div>
          <span style={{ color: isAnnual ? 'var(--text-espresso)' : 'var(--text-muted)' }}>
            Annual <span className="savings-tag">SAVE 20%</span>
          </span>
        </div>

        {/* Pricing Cards Grid */}
        <div className="pricing-grid">
          {/* Plan 1: Starter */}
          <div className="pricing-card">
            <h3 className="plan-name">Starter Café</h3>
            <p className="plan-desc">Perfect for quick-service kiosks, coffee shops, and small bakeries.</p>

            <div className="plan-price-wrap">
              <span className="plan-currency">₹</span>
              <span className="plan-amount">{isAnnual ? '799' : '999'}</span>
              <span className="plan-billing-term">/ month</span>
            </div>

            <ul className="plan-features-list">
              <li className="plan-feature-item">
                <Check size={18} />
                <span>1 Billing Terminal (Android or Windows)</span>
              </li>
              <li className="plan-feature-item">
                <Check size={18} />
                <span>100% Offline-First Durability</span>
              </li>
              <li className="plan-feature-item">
                <Check size={18} />
                <span>Unlimited Orders &amp; KOTs</span>
              </li>
              <li className="plan-feature-item">
                <Check size={18} />
                <span>5% GST Billing (CGST/SGST Breakdown)</span>
              </li>
              <li className="plan-feature-item">
                <Check size={18} />
                <span>End-of-Day Shift Z-Report</span>
              </li>
              <li className="plan-feature-item">
                <Check size={18} />
                <span>ESC/POS Thermal USB &amp; Bluetooth Print</span>
              </li>
            </ul>

            <button onClick={() => onOpenDemo('Starter')} className="btn btn-secondary" style={{ width: '100%' }}>
              Get Started with Starter
            </button>
          </div>

          {/* Plan 2: Pro Dining (Featured) */}
          <div className="pricing-card featured">
            <div className="pricing-featured-badge">MOST POPULAR FOR DINE-IN</div>
            <h3 className="plan-name">Pro Dining &amp; Bar</h3>
            <p className="plan-desc">For full-service restaurants, restro-bars, and busy family diners.</p>

            <div className="plan-price-wrap">
              <span className="plan-currency">₹</span>
              <span className="plan-amount">{isAnnual ? '1,599' : '1,999'}</span>
              <span className="plan-billing-term">/ month</span>
            </div>

            <ul className="plan-features-list">
              <li className="plan-feature-item">
                <Check size={18} />
                <span><strong>Up to 5 Terminals</strong> (Cashier + Waiter + KDS)</span>
              </li>
              <li className="plan-feature-item">
                <Check size={18} />
                <span><strong>Dedicated Kitchen Display (KDS)</strong> role</span>
              </li>
              <li className="plan-feature-item">
                <Check size={18} />
                <span>Table &amp; Floor Zones (AC, Garden, Bar)</span>
              </li>
              <li className="plan-feature-item">
                <Check size={18} />
                <span>Move &amp; Merge Active Tables</span>
              </li>
              <li className="plan-feature-item">
                <Check size={18} />
                <span>Manager PIN Re-Auth (Voids &amp; Discounts)</span>
              </li>
              <li className="plan-feature-item">
                <Check size={18} />
                <span>WhatsApp Digital Invoicing Delivery</span>
              </li>
              <li className="plan-feature-item">
                <Check size={18} />
                <span>Live Admin Revenue Dashboard</span>
              </li>
            </ul>

            <button onClick={() => onOpenDemo('Pro Dining')} className="btn btn-primary" style={{ width: '100%' }}>
              <Sparkles size={16} /> Choose Pro Dining
            </button>
          </div>

          {/* Plan 3: Enterprise */}
          <div className="pricing-card">
            <h3 className="plan-name">Enterprise &amp; Chain</h3>
            <p className="plan-desc">For multi-branch restaurant chains, franchises, and cloud kitchen hubs.</p>

            <div className="plan-price-wrap">
              <span className="plan-amount" style={{ fontSize: '2.4rem' }}>Custom</span>
              <span className="plan-billing-term">tailored quote</span>
            </div>

            <ul className="plan-features-list">
              <li className="plan-feature-item">
                <Check size={18} />
                <span>Unlimited Terminals &amp; Outlets</span>
              </li>
              <li className="plan-feature-item">
                <Check size={18} />
                <span>Centralized Menu &amp; Recipe Management</span>
              </li>
              <li className="plan-feature-item">
                <Check size={18} />
                <span>Cross-Outlet Raw Material Inventory</span>
              </li>
              <li className="plan-feature-item">
                <Check size={18} />
                <span>Custom ERP &amp; Tally Accounting Sync</span>
              </li>
              <li className="plan-feature-item">
                <Check size={18} />
                <span>Dedicated Success Manager &amp; 99.9% SLA</span>
              </li>
            </ul>

            <button onClick={() => onOpenDemo('Enterprise')} className="btn btn-secondary" style={{ width: '100%' }}>
              Talk to Sales
            </button>
          </div>
        </div>
      </div>
    </section>
  );
};
