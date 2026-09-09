import React from 'react';
import { Database, Zap, ChefHat, Calculator, CheckCircle2 } from 'lucide-react';

export const FeaturePillars: React.FC = () => {
  return (
    <section id="features" className="section">
      <div className="container">
        <div className="section-header">
          <span className="section-eyebrow">Architected for Indian F&B</span>
          <h2 className="section-title">The Four Pillars of Unstoppable Restaurant Operations</h2>
          <p className="section-desc">
            Designed to solve the real-world friction of dinner rushes: patchy internet, noisy kitchens, split bills, and end-of-day register shortages.
          </p>
        </div>

        <div className="feature-pillars-grid">
          {/* Pillar 1 */}
          <div className="feature-card">
            <div className="feature-icon-box icon-terracotta">
              <Database size={28} />
            </div>
            <h3 className="feature-card-title">100% Offline-First Durability</h3>
            <p className="feature-card-desc">
              Broadband down? Peak dinner rush? FoodPOS never stalls. Tables, orders, and bill closures write directly to local SQLite cache and automatically synchronize to the cloud upon reconnect without dropping a single payment event.
            </p>
            <div>
              <span className="feature-metric-badge">
                <CheckCircle2 size={14} style={{ color: 'var(--terracotta)' }} /> Survives app restarts & reboots
              </span>
            </div>
          </div>

          {/* Pillar 2 */}
          <div className="feature-card">
            <div className="feature-icon-box icon-spice">
              <Zap size={28} />
            </div>
            <h3 className="feature-card-title">90-Second Billing & Split Tender</h3>
            <p className="feature-card-desc">
              Rapid table settlement with Cash, UPI, and Card splits. Integer-paise billing math guarantees 100% precision for 5% GST (2.5% CGST + 2.5% SGST) and automated cash change calculations.
            </p>
            <div>
              <span className="feature-metric-badge">
                <CheckCircle2 size={14} style={{ color: 'var(--spice-ochre-dark)' }} /> p95 save latency &lt; 150ms
              </span>
            </div>
          </div>

          {/* Pillar 3 */}
          <div className="feature-card">
            <div className="feature-icon-box icon-emerald">
              <ChefHat size={28} />
            </div>
            <h3 className="feature-card-title">Paperless Kitchen Display (KDS)</h3>
            <p className="feature-card-desc">
              Eliminate paper roll expense and lost KOT slips. Chefs view live order tickets color-coded by prep time and advance them through an immutable FSM: New &rarr; Preparing &rarr; Ready &rarr; Served.
            </p>
            <div>
              <span className="feature-metric-badge">
                <CheckCircle2 size={14} style={{ color: 'var(--emerald-herbal)' }} /> Display-only restricted chef role
              </span>
            </div>
          </div>

          {/* Pillar 4 */}
          <div className="feature-card">
            <div className="feature-icon-box icon-espresso">
              <Calculator size={28} />
            </div>
            <h3 className="feature-card-title">Blind Cash Count & Z-Reports</h3>
            <p className="feature-card-desc">
              Prevent cash register theft and unrecorded payouts. Cashiers enter physical denomination counts at shift close, cross-referenced with sales, cash-in/out, and refunds to highlight variance immediately.
            </p>
            <div>
              <span className="feature-metric-badge">
                <CheckCircle2 size={14} style={{ color: 'var(--text-espresso)' }} /> Target variance &le; &plusmn;&inr;50 per shift
              </span>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};
