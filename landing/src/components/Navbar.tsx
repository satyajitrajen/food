import React from 'react';
import { useRouter } from '../router';
import { UtensilsCrossed, PhoneCall } from 'lucide-react';

interface NavbarProps {
  onOpenDemo: () => void;
}

export const Navbar: React.FC<NavbarProps> = ({ onOpenDemo }) => {
  const { navigate, currentPath } = useRouter();

  const handleNavClick = (e: React.MouseEvent<HTMLAnchorElement>, targetId: string) => {
    e.preventDefault();
    if (currentPath !== '/') {
      navigate('/');
    }
    setTimeout(() => {
      const element = document.getElementById(targetId);
      if (element) {
        element.scrollIntoView({ behavior: 'smooth' });
      }
    }, 60);
  };

  return (
    <header className="nav-wrapper">
      <nav className="nav-pill">
        {/* Brand */}
        <a href="/" onClick={(e) => { e.preventDefault(); navigate('/'); }} className="nav-brand">
          <div className="nav-brand-icon">
            <UtensilsCrossed size={18} />
          </div>
          <span>Food<span style={{ color: 'var(--orange-primary)' }}>POS</span></span>
        </a>

        {/* Center Pill Menu */}
        <ul className="nav-menu">
          <li>
            <a
              href="#simulator"
              onClick={(e) => handleNavClick(e, 'simulator')}
              className={`nav-pill-item ${currentPath === '/' ? 'active' : ''}`}
            >
              • Terminal
            </a>
          </li>
          <li>
            <a
              href="#features"
              onClick={(e) => handleNavClick(e, 'features')}
              className="nav-pill-item"
            >
              Pillars
            </a>
          </li>
          <li>
            <a
              href="#floors"
              onClick={(e) => handleNavClick(e, 'floors')}
              className="nav-pill-item"
            >
              Dining &amp; KDS
            </a>
          </li>
          <li>
            <a
              href="#pricing"
              onClick={(e) => handleNavClick(e, 'pricing')}
              className="nav-pill-item"
            >
              Pricing
            </a>
          </li>
          <li>
            <a
              href="#faq"
              onClick={(e) => handleNavClick(e, 'faq')}
              className="nav-pill-item"
            >
              FAQ
            </a>
          </li>
        </ul>

        {/* Right CTA */}
        <button onClick={onOpenDemo} className="nav-contact-btn">
          <PhoneCall size={15} />
          <span>Book Demo</span>
        </button>
      </nav>
    </header>
  );
};
