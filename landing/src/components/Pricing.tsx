import React from 'react';
import { Check } from 'lucide-react';
import { useRouter } from '../router';

// Plan code must match the backend catalog seeded in store/saas.go.
const PLAN_CODE = 'pro';

export const Pricing: React.FC = () => {
  const { navigate } = useRouter();

  return (
    <section id="pricing" className="p-section">
      <div className="t-container">
        {/* Section Header */}
        <h2 className="p-title">One simple plan</h2>

        {/* Single Plan Card (Featured) */}
        <div className="p-grid">
          <div className="p-card p-card-featured" style={{ maxWidth: 480, margin: '0 auto', width: '100%' }}>
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
              <span className="p-popular-badge">Annual</span>
            </div>

            <div className="p-card-featured-body">
              <p className="p-plan-desc">
                Everything a full-service restaurant needs — one price, one year, no hidden fees.
              </p>

              <div className="p-price-box">
                <div className="p-price-row">
                  <span className="p-price-val">₹1,999</span>
                  <div className="p-price-term">
                    <span>INR /</span>
                    <span>year</span>
                  </div>
                </div>
                <button
                  className="p-btn p-btn-secondary"
                  onClick={() => navigate(`/console/register?plan=${PLAN_CODE}`)}
                >
                  Start 7-day free trial
                </button>
              </div>

              <ul className="p-features">
                <li className="p-feature-item">
                  <Check size={16} strokeWidth={2.4} />
                  <span>Up to 5 Devices (POS + Kitchen Display + Waiter phones)</span>
                </li>
                <li className="p-feature-item">
                  <Check size={16} strokeWidth={2.4} />
                  <span>Up to 5 Outlets · 20 Staff Members</span>
                </li>
                <li className="p-feature-item">
                  <Check size={16} strokeWidth={2.4} />
                  <span>100% Offline-First Durability</span>
                </li>
                <li className="p-feature-item">
                  <Check size={16} strokeWidth={2.4} />
                  <span>Unlimited Orders &amp; KOTs · Dedicated KDS</span>
                </li>
                <li className="p-feature-item">
                  <Check size={16} strokeWidth={2.4} />
                  <span>Table &amp; Floor Zones (AC, Garden, Bar)</span>
                </li>
                <li className="p-feature-item">
                  <Check size={16} strokeWidth={2.4} />
                  <span>GST Billing + End-of-Day Z-Report</span>
                </li>
                <li className="p-feature-item">
                  <Check size={16} strokeWidth={2.4} />
                  <span>WhatsApp Digital Bills · Thermal Bluetooth &amp; USB Print</span>
                </li>
                <li className="p-feature-item">
                  <Check size={16} strokeWidth={2.4} />
                  <span>Reports, Inventory, Cash Drawer &amp; Staff Attendance</span>
                </li>
              </ul>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};
