import React from 'react';
import { Compass, Play, WifiOff, ChefHat, MapPin, Store } from 'lucide-react';

interface HeroProps {
  onOpenDemo: () => void;
  onScrollToSimulator: () => void;
}

export const Hero: React.FC<HeroProps> = ({ onOpenDemo, onScrollToSimulator }) => {
  return (
    <section className="hero-wrapper">
      {/* Contrasting Weight Headline Matching Reference */}
      <h1 className="hero-main-heading">
        <span className="heading-heavy">Master</span>{' '}
        <span className="heading-light">Restaurant Billing Straight</span>
        <br />
        <span className="heading-light">From The</span>{' '}
        <span className="heading-heavy">Counter</span>
      </h1>

      {/* Subtitle */}
      <p className="hero-subtext">
        Offline-tolerant Point-of-Sale engineered for Indian dining, cafés &amp; QSRs. Connect orders straight to the kitchen with zero network downtime, 90-second GST billing, and no middlemen.
      </p>

      {/* Dual Pill CTA Row */}
      <div className="hero-actions-row">
        <button onClick={onOpenDemo} className="btn-pill-primary">
          <Compass size={18} />
          <span>Book a Live Demo</span>
        </button>

        <button onClick={onScrollToSimulator} className="btn-pill-outline">
          <Play size={16} fill="currentColor" style={{ opacity: 0.8 }} />
          <span>Explore The Terminal</span>
        </button>
      </div>

      {/* Trust Micro-Pills (Matching Black Circular Icons in Reference) */}
      <div className="hero-micro-pills">
        <div className="micro-pill-item">
          <div className="micro-pill-icon">
            <WifiOff size={18} />
          </div>
          <div>
            <div className="micro-pill-title">100% Offline Outbox</div>
            <div className="micro-pill-desc">Keep billing when restaurant Wi-Fi drops</div>
          </div>
        </div>

        <div className="micro-pill-item">
          <div className="micro-pill-icon">
            <ChefHat size={18} />
          </div>
          <div>
            <div className="micro-pill-title">Direct KDS Dispatch</div>
            <div className="micro-pill-desc">Instant kitchen tickets without paper slip loss</div>
          </div>
        </div>
      </div>

      {/* Central Device Showcase with Orbital Floating Food Cards */}
      <div className="device-orbital-stage">
        {/* Dashed Curved Trajectory Lines */}
        <svg
          className="orbital-dashed-svg"
          viewBox="0 0 1080 640"
          fill="none"
          xmlns="http://www.w3.org/2000/svg"
        >
          {/* Curved path left */}
          <path
            d="M 180 140 C 260 260, 320 320, 390 350"
            stroke="#F4A261"
            strokeWidth="2"
            strokeDasharray="6 6"
            opacity="0.8"
          />
          {/* Curved path bottom */}
          <path
            d="M 220 520 C 340 600, 500 590, 570 540"
            stroke="#F4A261"
            strokeWidth="2"
            strokeDasharray="6 6"
            opacity="0.8"
          />
          {/* Curved path right */}
          <path
            d="M 900 160 C 800 240, 740 310, 690 350"
            stroke="#F4A261"
            strokeWidth="2"
            strokeDasharray="6 6"
            opacity="0.8"
          />
        </svg>

        {/* Floating Path Badges */}
        <div className="floating-path-badge badge-pos-left">
          <MapPin size={14} style={{ color: 'var(--orange-primary)' }} />
          <span>FC Road, Pune</span>
        </div>

        <div className="floating-path-badge badge-pos-bottom">
          <Store size={14} style={{ color: 'var(--color-emerald)' }} />
          <span>Local Device SQLite</span>
        </div>

        {/* Floating Card 1: Top Left (Biryani) */}
        <div className="orbital-card card-top-left">
          <img
            src="/images/hero-biryani.jpg"
            alt="Hyderabadi Dum Biryani"
            className="orbital-img"
          />
        </div>

        {/* Floating Card 2: Bottom Left (Street Food Vendor Counter) */}
        <div className="orbital-card card-bottom-left">
          <img
            src="/images/hero-vendor.jpg"
            alt="Indian Street Food Vendor Counter"
            className="orbital-img"
          />
        </div>

        {/* Center Mobile POS Screen Mockup */}
        <div className="center-phone-mockup">
          <div className="phone-screen">
            {/* Camera Notch */}
            <div className="phone-notch" />

            {/* Header bar */}
            <div className="phone-header">
              <div className="phone-location">
                <MapPin size={11} style={{ color: 'var(--orange-primary)' }} />
                <span>The Spice Pavilion</span>
              </div>
              <span className="phone-sync-badge">🟢 Sync Active</span>
            </div>

            {/* Quick search input */}
            <div className="phone-search-bar">
              <span>🔍 Search dishes or tables...</span>
            </div>

            {/* Active Table Order Card */}
            <div className="phone-order-card">
              <div className="phone-table-row">
                <strong style={{ fontSize: '0.8rem', color: '#1A1A1A' }}>Table T4 • AC Hall</strong>
                <span style={{ fontSize: '0.7rem', color: '#888', fontWeight: 600 }}>3 items</span>
              </div>

              <div className="phone-dish-item">
                <span>1x Dum Biryani</span>
                <strong>₹320</strong>
              </div>
              <div className="phone-dish-item">
                <span>1x Paneer Butter Masala</span>
                <strong>₹260</strong>
              </div>
              <div className="phone-dish-item">
                <span>2x Filter Coffee</span>
                <strong>₹120</strong>
              </div>

              <div style={{ marginTop: '8px', paddingTop: '6px', borderTop: '1px solid #ECE7DF', display: 'flex', justifyContent: 'space-between', fontSize: '0.75rem', fontWeight: 800 }}>
                <span>Total (incl. GST):</span>
                <span style={{ color: 'var(--orange-primary)' }}>₹735</span>
              </div>

              <div className="phone-fire-btn">
                Fire KOT &amp; Bill
              </div>
            </div>

            {/* Quick Category Chips */}
            <div style={{ padding: '0 14px', display: 'flex', gap: '6px', overflowX: 'hidden' }}>
              <span style={{ fontSize: '0.65rem', backgroundColor: '#EDE7DF', padding: '3px 8px', borderRadius: '12px', fontWeight: 700 }}>
                Biryani
              </span>
              <span style={{ fontSize: '0.65rem', backgroundColor: '#EDE7DF', padding: '3px 8px', borderRadius: '12px', fontWeight: 700 }}>
                Curries
              </span>
              <span style={{ fontSize: '0.65rem', backgroundColor: '#EDE7DF', padding: '3px 8px', borderRadius: '12px', fontWeight: 700 }}>
                Drinks
              </span>
            </div>

            {/* Bottom App Navigation */}
            <div className="phone-tab-bar">
              <span style={{ color: 'var(--orange-primary)', fontWeight: 700 }}>● Tables</span>
              <span>Orders</span>
              <span>KOT</span>
              <span>Shift</span>
            </div>
          </div>
        </div>

        {/* Floating Card 3: Top Right (Flames & Wok Cooking) */}
        <div className="orbital-card card-top-right">
          <img
            src="/images/hero-wok.jpg"
            alt="Chef Wok Cooking with Flames"
            className="orbital-img"
          />
        </div>

        {/* Floating Card 4: Bottom Right (Crispy Samosa & Jalebi) */}
        <div className="orbital-card card-bottom-right">
          <img
            src="/images/hero-samosa.jpg"
            alt="Crispy Samosa and Jalebi"
            className="orbital-img"
          />
        </div>
      </div>
    </section>
  );
};
