import React, { useState } from 'react';
import { Check } from 'lucide-react';
import { useRouter } from '../router';

// Plan codes must match the backend catalog seeded in store/saas.go.
const planCode = (base: string, isAnnual: boolean) => (isAnnual ? `${base}-annual` : base);

export const Pricing: React.FC = () => {
  const [isAnnual, setIsAnnual] = useState<boolean>(true);
  const { navigate } = useRouter();

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
                onClick={() => navigate(`/console/register?plan=${planCode('starter', isAnnual)}`)}
              >
                Choose Starter
              </button>
            </div>

            <ul className="p-features">
              <li className="p-feature-item">
                <Check size={16} strokeWidth={2.4} />
                <span>1 Billing Counter / Device (Android or Windows)</span>
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

          {/* Card 2: Pro Dining (Featured) */}
          <div className="p-card p-card-featured">
            <div className="p-banner">
              <svg className="p-banner-wave" viewBox="0 0 380 84" preserveAspectRatio="none" aria-hidden="true">
                <path
                  d="M0,48 C95,18 175,72 265,28 C315,2 350,38 380,24 L380,84 L0,84 Z"
                  fill="rgba(255, 255, 255, 0.05)"
                />
                <path
                  d="M0,64 C85,32 155,78 235,38 C295,8 340,52 380,32 L380,0 L0,0 Z"
                  fill="rgba(255, 107, 53, 0.12)"
                />
              </svg>
              <h3 className="p-banner-title">Pro Dining</h3>
              <span className="p-popular-badge">Most Popular</span>
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
                  onClick={() => navigate(`/console/register?plan=${planCode('pro', isAnnual)}`)}
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
                  <span>Up to 5 Devices (POS + Kitchen Display + Waiter phones)</span>
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
                onClick={() => navigate(`/console/register?plan=${planCode('chain', isAnnual)}`)}
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
                <span>Unlimited Devices &amp; Branch Outlets</span>
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
