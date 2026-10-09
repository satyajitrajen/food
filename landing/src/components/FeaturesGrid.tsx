import React from 'react';

interface BentoFeature {
  title: string;
  desc: string;
  image: string;
  imageAlt: string;
  variant: 'wide' | 'compact';
}

const BENTO_FEATURES: BentoFeature[] = [
  {
    title: 'Sales Reports & Z-Reports',
    desc: 'Sales by day, item, and payment mode, plus an end-of-shift Z-report that reconciles the register against a blind cash count so shortages surface the same night.',
    image: '/images/feature-reports.png',
    imageAlt: 'Sales report and Z-Report cash reconciliation screen',
    variant: 'wide',
  },
  {
    title: 'Live Kitchen Display & Order Flow',
    desc: 'Every KOT reaches the kitchen display the moment it is fired. Chefs move tickets from New to Preparing to Ready, and marking a ticket Ready notifies the floor.',
    image: '/images/feature-kot.png',
    imageAlt: 'Live Kitchen Display System (KDS) screen with active tickets',
    variant: 'wide',
  },
  {
    title: 'Visual Menu & Add-on Groups',
    desc: 'Full digital menu with dish photos, portion sizes, and custom modifier groups so staff punch accurate orders in seconds.',
    image: '/images/feature-menu.png',
    imageAlt: 'POS visual touch menu ordering with add-ons and variants',
    variant: 'compact',
  },
  {
    title: 'Instant WhatsApp Bills & Receipts',
    desc: 'Share the bill to your guest’s WhatsApp as a message or PDF, alongside or instead of a printed receipt.',
    image: '/images/feature-whatsapp.png',
    imageAlt: 'Bill shared to a guest on WhatsApp',
    variant: 'compact',
  },
  {
    title: 'Split Tender Payments',
    desc: 'Settle one bill across Cash, UPI, and Card with paise-exact math that always balances to the bill total. Works for dine-in, takeaway, and delivery orders.',
    image: '/images/feature-split.png',
    imageAlt: 'Split tender checkout across cash, UPI QR and card',
    variant: 'compact',
  },
];

export const FeaturesGrid: React.FC = () => {
  return (
    <section id="features" className="t-features">
      <div className="t-container">
        <div className="t-section-head">
          <span className="t-eyebrow">Valuable Features</span>
          <h2 className="t-section-title">Every Workflow Your Restaurant Runs On</h2>
          <p className="t-section-desc">
            Billing, kitchen, payments, and reports designed for real dinner rushes, not
            demo day. Built for Indian F&amp;B, from the counter up.
          </p>
        </div>

        <div className="t-bento-grid">
          {BENTO_FEATURES.map((f) => (
            <article
              className={`t-bento-card t-bento-card-${f.variant}`}
              key={f.title}
            >
              <div className="t-bento-media">
                <img
                  src={f.image}
                  alt={f.imageAlt}
                  className="t-bento-img"
                  loading="lazy"
                />
              </div>
              <div className="t-bento-body">
                <h3 className="t-bento-title">{f.title}</h3>
                <p className="t-bento-desc">{f.desc}</p>
              </div>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
};
