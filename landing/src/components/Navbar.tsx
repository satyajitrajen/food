import React, { useState, useEffect, useRef } from 'react';
import { useRouter } from '../router';
import { ArrowRight, Menu, X } from 'lucide-react';
import { REGISTER_PATH } from '../data/plan';

interface NavbarProps {
  onOpenDemo: () => void;
}

const NAV_LINKS = [
  { label: 'Features', targetId: 'features' },
  { label: 'Why Hishobkr', targetId: 'benefits' },
  { label: 'Hardware', targetId: 'hardware' },
  { label: 'Pricing', targetId: 'pricing' },
  { label: 'FAQ', targetId: 'faq' },
];

export const Navbar: React.FC<NavbarProps> = ({ onOpenDemo }) => {
  const { currentPath, navigate } = useRouter();
  const [isScrolled, setIsScrolled] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const toggleRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    const handleScroll = () => {
      setIsScrolled(window.scrollY > 8);
    };
    handleScroll();
    window.addEventListener('scroll', handleScroll, { passive: true });
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  // Esc closes the mobile panel and returns focus to the toggle.
  useEffect(() => {
    if (!menuOpen) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setMenuOpen(false);
        toggleRef.current?.focus();
      }
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [menuOpen]);

  // Close the panel if the viewport grows past the mobile breakpoint.
  useEffect(() => {
    const mq = window.matchMedia('(min-width: 901px)');
    const onChange = () => mq.matches && setMenuOpen(false);
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
  }, []);

  const handleNavClick = (e: React.MouseEvent<HTMLAnchorElement>, targetId: string) => {
    e.preventDefault();
    setMenuOpen(false);
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

  const startTrial = () => {
    setMenuOpen(false);
    navigate(REGISTER_PATH);
  };

  const openDemo = () => {
    setMenuOpen(false);
    onOpenDemo();
  };

  return (
    <header className={`t-header ${isScrolled || menuOpen ? 'is-scrolled' : ''}`}>
      <nav className="t-header-inner" aria-label="Main">
        {/* Brand */}
        <a href="/" onClick={(e) => { e.preventDefault(); setMenuOpen(false); navigate('/'); }} className="t-brand" aria-label="Hishobkr Home">
          <img src="/logo.png" alt="Hishobkr" className="t-brand-logo" />
        </a>

        {/* Center links (desktop) */}
        <ul className="t-nav-links">
          {NAV_LINKS.map((link) => (
            <li key={link.targetId}>
              <a href={`#${link.targetId}`} onClick={(e) => handleNavClick(e, link.targetId)}>
                {link.label}
              </a>
            </li>
          ))}
        </ul>

        <div className="t-nav-actions">
          <button type="button" onClick={onOpenDemo} className="t-nav-demo">
            Book a demo
          </button>
          <button type="button" onClick={startTrial} className="t-nav-cta">
            <span>Start free trial</span>
            <ArrowRight size={16} className="t-arrow" aria-hidden="true" />
          </button>
          <button
            ref={toggleRef}
            type="button"
            className="t-nav-toggle"
            aria-expanded={menuOpen}
            aria-controls="t-mobile-menu"
            aria-label={menuOpen ? 'Close menu' : 'Open menu'}
            onClick={() => setMenuOpen((v) => !v)}
          >
            {menuOpen ? <X size={22} aria-hidden="true" /> : <Menu size={22} aria-hidden="true" />}
          </button>
        </div>
      </nav>

      {/* Mobile panel */}
      <div id="t-mobile-menu" className="t-mobile-panel" hidden={!menuOpen}>
        <ul>
          {NAV_LINKS.map((link) => (
            <li key={link.targetId}>
              <a href={`#${link.targetId}`} onClick={(e) => handleNavClick(e, link.targetId)}>
                {link.label}
              </a>
            </li>
          ))}
        </ul>
        <div className="t-mobile-actions">
          <button type="button" onClick={startTrial} className="t-btn t-btn-dark">
            Start 7-day free trial
            <ArrowRight size={18} className="t-arrow" aria-hidden="true" />
          </button>
          <button type="button" onClick={openDemo} className="t-btn t-btn-outline">
            Book a demo
          </button>
        </div>
      </div>
    </header>
  );
};
