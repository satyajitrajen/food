import React, { useState } from 'react';
import { Check } from 'lucide-react';

interface PricingProps {
  onOpenDemo: (planName?: string) => void;
}

export const Pricing: React.FC<PricingProps> = ({ onOpenDemo }) => {
  const [isAnnual, setIsAnnual] = useState<boolean>(true);

  return (
    <section id="pricing" className="p-section">
      <div className="t-container">
        {/* Section Header */}
        <h2 className="p-title">Choose your plan</h2>

        {/* Toggle pill */}
        <div className="p-toggle-wrap">
          <div className="p-toggle-pill">
            <button
              className={`p-toggle-btn ${!isAnnual ? 'active' : ''}`}
              onClick={() => setIsAnnual(false)}
            >
              Pay monthly
            </button>
            <button
              className={`p-toggle-btn ${isAnnual ? 'active' : ''}`}
              onClick={() => setIsAnnual(true)}
            >
              <span>Pay yearly</span>
              <span className="p-green-dot" title="20% discount on yearly" />
            </button>
          </div>
        </div>

        {/* 3-Column Pricing Grid */}
        <div className="p-grid">
          {/* Card 1: Starter Café */}
          <div className="p-card">
            <h3 className="p-plan-name">Starter Café</h3>
            <p className="p-plan-desc">
              Perfect for quick-service kiosks, cafés, food trucks, and small bakeries.
            </p>

            <div className="p-price-box">
              <div className="p-price-row">
                <span className="p-price-val">
                  {isAnnual ? '₹799' : '₹999'}
                </span>
                <div className="p-price-term">
                  <span>INR /</span>
                  <span>month</span>
                </div>
              </div>
              <button
                className="p-btn p-btn-secondary"
                onClick={() => onOpenDemo('Starter Café')}
              >
                Choose Starter
              </button>
            </div>

            <ul className="p-features">
              <li className="p-feature-item">
                <Check size={16} strokeWidth={2.4} />
                <span>1 Billing Terminal (Android or Windows)</span>
              </li>
              <li className="p-feature-item">
                <Check size={16} strokeWidth={2.4} />
                <span>100% Offline-First Durability</span>
              </li>
              <li className="p-feature-item">
                <Check size={16} strokeWidth={2.4} />
                <span>Unlimited Orders &amp; KOTs</span>
              </li>
              <li className="p-feature-item">
                <Check size={16} strokeWidth={2.4} />
                <span>5% GST Billing (CGST/SGST Breakdown)</span>
              </li>
              <li className="p-feature-item">
                <Check size={16} strokeWidth={2.4} />
                <span>End-of-Day Shift Z-Report</span>
              </li>
              <li className="p-feature-item">
                <Check size={16} strokeWidth={2.4} />
                <span>Thermal Bluetooth &amp; USB Print</span>
              </li>
            </ul>
          </div>

          {/* Card 2: Pro Dining (Featured with Dark Fluid Banner) */}
          <div className="p-card p-card-featured">
            <div className="p-banner">
              <img
                src="/images/pricing-pro-banner.jpg"
                alt="Pro Dining dark fluid banner"
                className="p-banner-img"
              />
              <h3 className="p-banner-title">Pro Dining</h3>
            </div>

            <div className="p-card-featured-body">
              <p className="p-plan-desc">
                For full-service dining, restro-bars, and multi-floor busy restaurants.
              </p>

              <div className="p-price-box">
                <div className="p-price-row">
                  <span className="p-price-val">
                    {isAnnual ? '₹1,599' : '₹1,999'}
                  </span>
                  <div className="p-price-term">
                    <span>INR /</span>
                    <span>month</span>
                  </div>
                </div>
                <button
                  className="p-btn p-btn-secondary"
                  onClick={() => onOpenDemo('Pro Dining')}
                >
                  Choose Pro Dining
                </button>
              </div>

              <ul className="p-features">
                <li className="p-feature-item">
                  <Check size={16} strokeWidth={2.4} />
                  <span><strong>Everything in Starter Café</strong></span>
                </li>
                <li className="p-feature-item">
                  <Check size={16} strokeWidth={2.4} />
                  <span>Up to 5 Terminals (POS + KDS + Waiters)</span>
                </li>
                <li className="p-feature-item">
                  <Check size={16} strokeWidth={2.4} />
                  <span>Dedicated Kitchen Display System (KDS)</span>
                </li>
                <li className="p-feature-item">
                  <Check size={16} strokeWidth={2.4} />
                  <span>Table &amp; Floor Zones (AC, Garden, Bar)</span>
                </li>
                <li className="p-feature-item">
                  <Check size={16} strokeWidth={2.4} />
                  <span>WhatsApp Digital Bill Invoicing</span>
                </li>
                <li className="p-feature-item">
                  <Check size={16} strokeWidth={2.4} />
                  <span>Manager PIN Re-Auth (Discounts &amp; Voids)</span>
                </li>
              </ul>
            </div>
          </div>

          {/* Card 3: Multi-Outlet Chain */}
          <div className="p-card">
            <h3 className="p-plan-name">Multi-Outlet Chain</h3>
            <p className="p-plan-desc">
              For expanding restaurant chains, cloud kitchen hubs, and franchises.
            </p>

            <div className="p-price-box">
              <div className="p-price-row">
                <span className="p-price-val">
                  {isAnnual ? '₹3,199' : '₹3,999'}
                </span>
                <div className="p-price-term">
                  <span>INR /</span>
                  <span>month</span>
                </div>
              </div>
              <button
                className="p-btn p-btn-dark"
                onClick={() => onOpenDemo('Multi-Outlet Chain')}
              >
                Get Multi-Outlet
              </button>
            </div>

            <ul className="p-features">
              <li className="p-feature-item">
                <Check size={16} strokeWidth={2.4} />
                <span><strong>Everything in Pro Dining</strong></span>
              </li>
              <li className="p-feature-item">
                <Check size={16} strokeWidth={2.4} />
                <span>Unlimited Terminals &amp; Branch Outlets</span>
              </li>
              <li className="p-feature-item">
                <Check size={16} strokeWidth={2.4} />
                <span>Centralized Menu &amp; Recipe Management</span>
              </li>
              <li className="p-feature-item">
                <Check size={16} strokeWidth={2.4} />
                <span>Cross-Outlet Raw Material Inventory</span>
              </li>
              <li className="p-feature-item">
                <Check size={16} strokeWidth={2.4} />
                <span>Custom ERP &amp; Tally Accounting Sync</span>
              </li>
              <li className="p-feature-item">
                <Check size={16} strokeWidth={2.4} />
                <span>Dedicated Success Manager &amp; 99.9% SLA</span>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </section>
  );
};
