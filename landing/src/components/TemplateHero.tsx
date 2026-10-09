import React from 'react';
import {
  ArrowRight,
  Check,
} from 'lucide-react';
import { useRouter } from '../router';
import { PLAN, REGISTER_PATH } from '../data/plan';

interface TemplateHeroProps {
  onOpenDemo: () => void;
}

export const TemplateHero: React.FC<TemplateHeroProps> = ({ onOpenDemo }) => {
  const { navigate } = useRouter();

  return (
    <section className="t-hero">
      <div className="t-hero-glow" aria-hidden="true" />

      <div className="t-container t-hero-container">
        {/* Announcement pill */}
        <div className="t-hero-pill">
          <span className="t-hero-pill-new">New</span>
          <span className="t-hero-pill-dot" aria-hidden="true" />
          <span className="t-hero-pill-text">WhatsApp bills &amp; split payments</span>
        </div>

        {/* Headline */}
        <h1 className="t-hero-title">
          Perfect Every Service,
          <br />
          From Counter to Kitchen to Bill.
        </h1>

        <p className="t-hero-sub">
          Hishobkr runs billing, kitchen tickets, split payments, and WhatsApp bills on one
          screen, and keeps taking orders when the Wi-Fi drops in the middle of a dinner rush.
        </p>

        {/* Check feature pills */}
        <ul className="t-hero-checks">
          <li>
            <Check size={16} aria-hidden="true" /> Offline-first billing
          </li>
          <li>
            <Check size={16} aria-hidden="true" /> KOTs to the kitchen display
          </li>
          <li>
            <Check size={16} aria-hidden="true" /> Configurable GST
          </li>
        </ul>

        {/* CTAs */}
        <div className="t-hero-ctas">
          <button className="t-btn t-btn-dark" onClick={() => navigate(REGISTER_PATH)}>
            Start {PLAN.trialDays}-day free trial
            <ArrowRight size={18} className="t-arrow" aria-hidden="true" />
          </button>
          <button className="t-btn t-btn-outline" onClick={onOpenDemo}>
            Book a demo
            <ArrowRight size={18} className="t-arrow" aria-hidden="true" />
          </button>
        </div>

        {/* Audience strip */}
        <p className="t-hero-proof-line">Built for the way India actually dines</p>
        <ul className="t-hero-logos" aria-label="Restaurant types served">
          <li>Family Dining</li>
          <li>Cafés</li>
          <li>QSR</li>
          <li>Takeaway &amp; Delivery</li>
          <li>Cloud Kitchens</li>
        </ul>
      </div>
    </section>
  );
};
