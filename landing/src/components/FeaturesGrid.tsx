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
    title: 'Real-Time Sales & Z-Reports',
    desc: 'Track live revenue, hourly sales velocity, and peak dining trends. Automated end-of-day Z-reports reconcile the register and eliminate cash drawer shortages.',
    image: '/images/feature-reports.png',
    imageAlt: 'Restaurant sales revenue analytics and Z-Report cashier reconciliation',
    variant: 'wide',
  },
  {
    title: 'Live Kitchen Display & Order Flow',
    desc: 'Every order shoots to the kitchen the second it is punched. Chefs progress tickets from New to Ready in one tap, notifying servers the instant food is up.',
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
    desc: 'Send clean, branded PDF bills straight to your guest’s WhatsApp. Eliminate paper roll expenses and thermal printer jams.',
    image: '/images/feature-whatsapp.png',
    imageAlt: 'Instant WhatsApp digital bill receipt and PDF delivery',
    variant: 'compact',
  },
  {
    title: 'Flexible Split Tender Payments',
    desc: 'Split any check across Cash, UPI QR code, and Card simultaneously with integer-paise math that always balances to the exact rupee.',
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
