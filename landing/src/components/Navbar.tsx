import React from 'react';
import { useRouter } from '../router';
import { ArrowRight, UtensilsCrossed } from 'lucide-react';

interface NavbarProps {
  onOpenDemo: () => void;
}

const NAV_LINKS = [
  { label: 'Features', targetId: 'features' },
  { label: 'Benefits', targetId: 'benefits' },
  { label: 'Pricing', targetId: 'pricing' },
];

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
    <header className="t-header">
      <nav className="t-header-inner" aria-label="Main">
        {/* Brand */}
        <a href="/" onClick={(e) => { e.preventDefault(); navigate('/'); }} className="t-brand">
          <span className="t-brand-mark">
            <UtensilsCrossed size={18} />
          </span>
          <span>FoodPOS</span>
        </a>

        {/* Center links */}
        <ul className="t-nav-links">
          {NAV_LINKS.map((link) => (
            <li key={link.targetId}>
              <a href={`#${link.targetId}`} onClick={(e) => handleNavClick(e, link.targetId)}>
                {link.label}
              </a>
            </li>
          ))}
        </ul>

        {/* CTA */}
        <button onClick={onOpenDemo} className="t-nav-cta">
          <span>Get FoodPOS</span>
          <ArrowRight size={16} className="t-arrow" aria-hidden="true" />
        </button>
      </nav>
    </header>
  );
};
