import React from 'react';
import { useRouter } from '../router';
import { UtensilsCrossed, MessageCircle, Mail, MapPin } from 'lucide-react';

export const Footer: React.FC = () => {
  const { navigate } = useRouter();

  const handleLink = (e: React.MouseEvent<HTMLAnchorElement>, path: string) => {
    e.preventDefault();
    navigate(path);
  };

  const handleSection = (e: React.MouseEvent<HTMLAnchorElement>, sectionId: string) => {
    e.preventDefault();
    navigate('/');
    setTimeout(() => {
      const el = document.getElementById(sectionId);
      if (el) el.scrollIntoView({ behavior: 'smooth' });
    }, 50);
  };

  return (
    <footer className="footer">
      <div className="container">
        <div className="footer-grid">
          {/* Brand Col */}
          <div className="footer-brand">
            <div className="nav-logo" style={{ marginBottom: '12px' }}>
              <div className="nav-logo-icon">
                <UtensilsCrossed size={20} />
              </div>
              <span>Food<span style={{ color: 'var(--terracotta)' }}>POS</span></span>
            </div>
            <p>
              The offline-first restaurant POS engineered for Indian dining, cafés, and QSRs. Fast billing, instant KOTs, and zero downtime.
            </p>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', fontSize: '0.85rem', color: 'var(--text-muted)' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <MapPin size={14} style={{ color: 'var(--terracotta)' }} />
                <span>Pune, Maharashtra, India</span>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <Mail size={14} style={{ color: 'var(--terracotta)' }} />
                <span>support@foodpos.app</span>
              </div>
            </div>
          </div>

          {/* Product Col */}
          <div>
            <h4 className="footer-heading">Product</h4>
            <ul className="footer-links">
              <li>
                <a href="#simulator" onClick={(e) => handleSection(e, 'simulator')}>
                  Live POS Simulator
                </a>
              </li>
              <li>
                <a href="#features" onClick={(e) => handleSection(e, 'features')}>
                  4 Core Pillars
                </a>
              </li>
              <li>
                <a href="#floors" onClick={(e) => handleSection(e, 'floors')}>
                  Floor Map &amp; KDS
                </a>
              </li>
              <li>
                <a href="#pricing" onClick={(e) => handleSection(e, 'pricing')}>
                  Pricing Plans
                </a>
              </li>
              <li>
                <a href="#faq" onClick={(e) => handleSection(e, 'faq')}>
                  FAQ
                </a>
              </li>
            </ul>
          </div>

          {/* Compliance & Google Play Legal Col */}
          <div>
            <h4 className="footer-heading">Play Store Compliance</h4>
            <ul className="footer-links">
              <li>
                <a href="/privacy-policy" onClick={(e) => handleLink(e, '/privacy-policy')}>
                  Privacy Policy
                </a>
              </li>
              <li>
                <a href="/data-deletion" onClick={(e) => handleLink(e, '/data-deletion')}>
                  Account &amp; Data Deletion
                </a>
              </li>
              <li>
                <a href="/terms" onClick={(e) => handleLink(e, '/terms')}>
                  Terms of Service
                </a>
              </li>
              <li>
                <a href="/refund-policy" onClick={(e) => handleLink(e, '/refund-policy')}>
                  Refund Policy
                </a>
              </li>
            </ul>
          </div>

          {/* Connect Col */}
          <div>
            <h4 className="footer-heading">Connect</h4>
            <ul className="footer-links">
              <li>
                <a
                  href="https://wa.me/919822000000?text=Hi%20FoodPOS%2C%20I%20would%20like%20to%20speak%20with%20a%20product%20specialist."
                  target="_blank"
                  rel="noopener noreferrer"
                  style={{ display: 'inline-flex', alignItems: 'center', gap: '6px', color: '#25D366', fontWeight: 600 }}
                >
                  <MessageCircle size={16} /> WhatsApp Support
                </a>
              </li>
              <li>
                <span style={{ fontSize: '0.85rem', color: 'var(--text-muted)' }}>
                  Monday &ndash; Sunday: 9 AM &ndash; 11 PM IST
                </span>
              </li>
            </ul>
          </div>
        </div>

        {/* Footer Bottom */}
        <div className="footer-bottom">
          <div>
            &copy; {new Date().getFullYear()} FoodPOS Technologies India. All rights reserved.
          </div>
          <div style={{ display: 'flex', gap: '20px' }}>
            <a href="/privacy-policy" onClick={(e) => handleLink(e, '/privacy-policy')} style={{ color: 'var(--text-dim)' }}>
              Privacy
            </a>
            <a href="/data-deletion" onClick={(e) => handleLink(e, '/data-deletion')} style={{ color: 'var(--text-dim)' }}>
              Data Deletion
            </a>
            <a href="/terms" onClick={(e) => handleLink(e, '/terms')} style={{ color: 'var(--text-dim)' }}>
              Terms
            </a>
          </div>
        </div>
      </div>
    </footer>
  );
};
