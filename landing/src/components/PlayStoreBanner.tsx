import React from 'react';
import { Tablet, Monitor, Printer, Globe, ArrowRight } from 'lucide-react';
import { useRouter } from '../router';
import { PLAN, REGISTER_PATH } from '../data/plan';

interface PlayStoreBannerProps {
  onOpenDemo: () => void;
}

const DEVICES = [
  { icon: Tablet, label: 'Android tablets & phones', note: 'Captain ordering' },
  { icon: Monitor, label: 'Windows desktop billing counter', note: 'Cashier' },
  { icon: Globe, label: 'Any modern browser', note: 'Owner & kitchen screens' },
  { icon: Printer, label: 'ESC/POS thermal printers (80 mm)', note: 'LAN / Wi-Fi' },
];

export const PlayStoreBanner: React.FC<PlayStoreBannerProps> = ({ onOpenDemo }) => {
  const { navigate } = useRouter();

  return (
    <section id="hardware" className="section" style={{ padding: '40px 0' }}>
      <div className="t-container">
        <div className="playstore-banner">
          <div className="playstore-grid">
            <div>
              <span className="hero-pill-badge playstore-eyebrow">
                NO PROPRIETARY HARDWARE
              </span>
              <h2 className="playstore-title">
                Runs on the Tablets and PCs You Already Have
              </h2>
              <p className="playstore-desc">
                No hardware lock-in. Captains take orders on everyday Android tablets or phones,
                the counter bills from a Windows PC, and receipts go to a network thermal printer.
              </p>

              <div className="playstore-badges">
                <button type="button" className="t-btn t-btn-light" onClick={() => navigate(REGISTER_PATH)}>
                  Start {PLAN.trialDays}-day free trial
                  <ArrowRight size={18} aria-hidden="true" />
                </button>
                <button type="button" className="badge-button" onClick={onOpenDemo}>
                  Talk to us
                </button>
              </div>
            </div>

            {/* Supported devices */}
            <div className="playstore-device-mock">
              <div className="playstore-device-head">Supported devices</div>
              {DEVICES.map(({ icon: Icon, label, note }) => (
                <div className="device-row" key={label}>
                  <div className="device-row-label">
                    <Icon size={18} aria-hidden="true" />
                    <span>{label}</span>
                  </div>
                  <span className="device-row-note">{note}</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};
