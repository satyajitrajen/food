import React from 'react';
import {
  ArrowRight,
  Check,
} from 'lucide-react';

interface TemplateHeroProps {
  onOpenDemo: () => void;
  onScrollToFeatures: () => void;
}

export const TemplateHero: React.FC<TemplateHeroProps> = ({
  onOpenDemo,
  onScrollToFeatures,
}) => {
  return (
    <section className="t-hero">
      <div className="t-hero-glow" aria-hidden="true" />

      <div className="t-container t-hero-container">
        {/* Announcement pill */}
        <div className="t-hero-pill">
          <span className="t-hero-pill-new">New</span>
          <span className="t-hero-pill-dot" aria-hidden="true" />
          <span className="t-hero-pill-text">WhatsApp bills &amp; split payments are live</span>
        </div>

        {/* Headline */}
        <h1 className="t-hero-title">
          Perfect Every Service,
          <br />
          From Counter to Kitchen to Bill.
        </h1>

        <p className="t-hero-sub">
          FoodPOS runs billing, kitchen tickets, split payments, and WhatsApp bills on one
          screen, even when the Wi-Fi drops in the middle of a dinner rush.
        </p>

        {/* Check feature pills */}
        <ul className="t-hero-checks">
          <li>
            <Check size={16} aria-hidden="true" /> Billing in 90 seconds
          </li>
          <li>
            <Check size={16} aria-hidden="true" /> Works 100% offline
          </li>
          <li>
            <Check size={16} aria-hidden="true" /> 5% GST accurate
          </li>
        </ul>

        {/* CTAs */}
        <div className="t-hero-ctas">
          <button className="t-btn t-btn-dark" onClick={onScrollToFeatures}>
            Explore FoodPOS
            <ArrowRight size={18} className="t-arrow" aria-hidden="true" />
          </button>
          <button className="t-btn t-btn-outline" onClick={onOpenDemo}>
            Request a Demo
            <ArrowRight size={18} className="t-arrow" aria-hidden="true" />
          </button>
        </div>

        {/* Proof strip */}
        <p className="t-hero-proof-line">Built for the way India actually dines</p>
        <ul className="t-hero-logos" aria-label="Restaurant types served">
          <li>Family Dining</li>
          <li>Cafés</li>
          <li>QSR</li>
          <li>Bars &amp; Lounges</li>
          <li>Cloud Kitchens</li>
        </ul>
      </div>
    </section>
  );
};
