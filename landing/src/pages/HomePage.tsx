import React, { useState } from 'react';
import {
  ArrowRight,
  BarChart3,
  Bluetooth,
  ChefHat,
  Globe,
  Mail,
  Monitor,
  Network,
  Package,
  Printer,
  QrCode,
  Smartphone,
  Tablet,
  Usb,
  WifiOff,
  Check,
} from 'lucide-react';
import { useRouter } from '../router';
import { PLAN, REGISTER_PATH } from '../data/plan';
import { Pricing } from '../components/Pricing';
import { FAQ } from '../components/FAQ';
import { createLead, SUPPORT_EMAIL, WHATSAPP_NUMBER } from '../console/api';

const APP_STORE_URL = 'https://apps.apple.com/in/app/hishobkr/id6826670862';
const WEB_APP_URL = '/login/';
const PLAY_STORE_URL = 'https://play.google.com/store/apps/details?id=com.hishobkr.foodpos';

interface HomePageProps {
  onOpenDemo: (plan?: string) => void;
}

/* ---------- small building blocks ---------- */

const Phone: React.FC<{ src: string; alt: string; className?: string; eager?: boolean }> = ({ src, alt, className = '', eager }) => (
  <div className={`h-phone ${className}`}>
    <div className="h-phone-notch" aria-hidden="true" />
    <img src={src} alt={alt} loading={eager ? 'eager' : 'lazy'} />
  </div>
);

const AppleIcon = () => (
  <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" fill="currentColor">
    <path d="M16.37 12.6c-.02-2.3 1.88-3.4 1.96-3.46-1.07-1.56-2.73-1.78-3.32-1.8-1.41-.14-2.76.83-3.48.83-.72 0-1.82-.81-3-.79-1.54.02-2.97.9-3.76 2.28-1.6 2.78-.41 6.9 1.15 9.16.76 1.1 1.67 2.34 2.86 2.3 1.15-.05 1.58-.74 2.97-.74 1.38 0 1.77.74 2.98.72 1.23-.02 2.01-1.12 2.76-2.23.87-1.28 1.23-2.52 1.25-2.58-.03-.01-2.39-.92-2.41-3.64zM14.1 5.86c.63-.77 1.06-1.83.94-2.89-.91.04-2.02.61-2.67 1.37-.58.67-1.1 1.76-.96 2.8 1.02.08 2.06-.52 2.69-1.28z" />
  </svg>
);

const PlayIcon = () => (
  <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true">
    <path fill="#34A853" d="M3.6 1.8 13.3 11.5 3.6 21.2c-.4-.2-.6-.6-.6-1.1V2.9c0-.5.2-.9.6-1.1z" />
    <path fill="#FBBC04" d="m16.5 14.7-3.2-3.2 3.2-3.2 3.7 2.1c1 .6 1 1.6 0 2.2l-3.7 2.1z" />
    <path fill="#4285F4" d="M16.5 14.7 13.3 11.5 3.6 21.2c.4.2.9.2 1.4-.1l11.5-6.4z" />
    <path fill="#EA4335" d="M16.5 8.3 5 1.9c-.5-.3-1-.3-1.4-.1l9.7 9.7 3.2-3.2z" />
  </svg>
);

const WhatsAppIcon = ({ size = 20 }: { size?: number }) => (
  <svg viewBox="0 0 24 24" width={size} height={size} aria-hidden="true" fill="currentColor">
    <path d="M17.5 14.4c-.3-.1-1.8-.9-2-1-.3-.1-.5-.1-.7.1-.2.3-.8 1-.9 1.2-.2.2-.3.2-.6.1-.3-.1-1.3-.5-2.4-1.5-.9-.8-1.5-1.8-1.7-2.1-.2-.3 0-.5.1-.6l.4-.5c.2-.2.2-.3.3-.5.1-.2 0-.4 0-.5l-.9-2.2c-.2-.6-.5-.5-.7-.5h-.6c-.2 0-.5.1-.8.4-.3.3-1 1-1 2.5s1.1 2.9 1.2 3.1c.1.2 2.1 3.2 5.1 4.5.7.3 1.3.5 1.7.6.7.2 1.4.2 1.9.1.6-.1 1.8-.7 2-1.4.2-.7.2-1.3.2-1.4-.1-.2-.3-.3-.6-.4zM12 21.8c-1.8 0-3.5-.5-5-1.4l-.4-.2-3.7 1 1-3.6-.2-.4C2.7 15.6 2.2 13.8 2.2 12 2.2 6.6 6.6 2.2 12 2.2c2.6 0 5.1 1 6.9 2.9 1.8 1.8 2.9 4.3 2.9 6.9 0 5.4-4.4 9.8-9.8 9.8zm8.4-18.2C18.1 1.3 15.2.1 12 .1 5.5.1.2 5.4.2 11.9c0 2.1.5 4.1 1.6 5.9L.1 23.9l6.3-1.6c1.7.9 3.7 1.4 5.6 1.4 6.5 0 11.8-5.3 11.8-11.8 0-3.2-1.2-6.1-3.4-8.3z" />
  </svg>
);

const StoreButtons: React.FC<{ dark?: boolean }> = ({ dark }) => (
  <div className={`h-stores ${dark ? 'is-dark' : ''}`}>
    <a className="h-store" href={PLAY_STORE_URL} target="_blank" rel="noopener noreferrer">
      <PlayIcon />
      <span>
        <small>Get it on</small>
        Google Play
      </span>
    </a>
    <a className="h-store" href={APP_STORE_URL} target="_blank" rel="noopener noreferrer">
      <AppleIcon />
      <span>
        <small>Download on the</small>
        App Store
      </span>
    </a>
    <a className="h-store" href={WEB_APP_URL}>
      <Globe size={20} aria-hidden="true" />
      <span>
        <small>Open in your</small>
        Web Browser
      </span>
    </a>
  </div>
);

const Eyebrow: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <span className="h-eyebrow">{children}</span>
);

/* ---------- content (all from the shipping app) ---------- */

const RIBBON = ['Fast Billing', 'Kitchen KOTs', 'Table Management', 'Inventory', 'Daily Reports', 'WhatsApp Bills'];

const BENEFITS_LEFT = [
  {
    icon: WifiOff,
    title: 'Works Offline',
    text: 'Keep billing when the internet drops. Orders queue on the device and sync on their own once you are back online.',
  },
  {
    icon: ChefHat,
    title: 'KOTs & Kitchen Display',
    text: 'Send kitchen tickets with one tap. The kitchen screen shows every order, and cooks mark it preparing and ready.',
  },
];

const BENEFITS_RIGHT = [
  {
    icon: BarChart3,
    title: 'Reports & Shift Close',
    text: 'Daily gross and net sales, category breakdown, cash drawer ledger and a printable Z-report at shift close.',
  },
  {
    icon: Package,
    title: 'Inventory & Suppliers',
    text: 'Track raw materials with minimum stock levels, record purchases, and keep a ledger of supplier payments.',
  },
];

const STEPS = [
  {
    title: 'Set Up Your Restaurant',
    text: `Create your restaurant from the web or the app and start a ${PLAN.trialDays}-day free trial. No card needed. Add your GSTIN, tax rate, UPI ID and outlet details once.`,
    points: ['Owner console on the web', 'Up to 5 outlets on one account', 'GST (CGST/SGST) on every bill'],
    img: '/images/app/more.png',
    alt: 'Hishobkr restaurant operations screen',
    chip: 'Restaurant profile, tax, UPI & printers',
  },
  {
    title: 'Add Your Menu & Tables',
    text: 'Build your menu with categories, prices, variants and add-ons, and switch items off when they run out. Lay out your sections and tables with seat counts.',
    points: ['Variants & modifiers', 'Veg / non-veg markers', 'Customer menu QR for guests'],
    img: '/images/app/menu.png',
    alt: 'Hishobkr menu management screen',
    chip: 'Butter Chicken · ₹190 · 2 variants',
  },
  {
    title: 'Take Orders & Send KOTs',
    text: 'Take dine-in, takeaway and delivery orders from the same screen. Pick a table, add items and send the KOT straight to the kitchen printer or display.',
    points: ['Move & merge tables', 'Running orders at a glance', 'Ready-to-serve alerts'],
    img: '/images/app/tables.png',
    alt: 'Hishobkr floor tables screen',
    chip: '8 Free / 8 Total',
  },
  {
    title: 'Bill, Collect & Close the Day',
    text: 'Collect by cash, UPI, card or split payment, give credit to regulars, and share the bill on WhatsApp. Close the shift with a cash count and Z-report.',
    points: ['Split & credit (pay later) bills', 'Discounts, charges & refunds', 'Expenses & cash in/out'],
    img: '/images/app/pos.png',
    alt: 'Hishobkr POS billing screen',
    chip: 'Cash · UPI · Card · Split',
  },
];

const DEVICES = [
  { icon: Bluetooth, label: 'Bluetooth Printers' },
  { icon: Usb, label: 'USB Printers' },
  { icon: Network, label: 'LAN / Wi-Fi Printers' },
  { icon: Printer, label: 'Built-in POS Printers' },
  { icon: Smartphone, label: 'Android & iPhone' },
  { icon: Tablet, label: 'Tablets & iPad' },
  { icon: Monitor, label: 'Web Browser' },
];

/* ---------- sections ---------- */

const Hero: React.FC<{ onOpenDemo: () => void }> = ({ onOpenDemo }) => {
  const { navigate } = useRouter();
  return (
    <section className="h-hero" id="home">
      <div className="h-container h-hero-copy">
        <h1>All-in-one Restaurant Billing App</h1>
        <p>
          Take orders, send KOTs to the kitchen, bill in seconds and see today&apos;s sales, on your phone,
          tablet or browser. Even when the internet is down.
        </p>
        <StoreButtons />
        <div className="h-hero-links">
          <button type="button" onClick={() => navigate(REGISTER_PATH)}>
            Start {PLAN.trialDays}-day free trial <ArrowRight size={15} aria-hidden="true" />
          </button>
          <span aria-hidden="true">·</span>
          <button type="button" onClick={onOpenDemo}>Book a demo</button>
        </div>
      </div>

      <div className="h-hero-stage">
        <div className="h-hero-sun" aria-hidden="true" />
        <Phone src="/images/app/tables.png" alt="Floor tables screen" className="is-left" eager />
        <Phone src="/images/app/pos.png" alt="POS billing screen" className="is-center" eager />
        <Phone src="/images/app/menu.png" alt="Menu management screen" className="is-right" eager />
      </div>

      <div className="h-ribbon" aria-label="What Hishobkr does">
        <ul>
          {[...RIBBON, ...RIBBON].map((r, i) => (
            <li key={i} aria-hidden={i >= RIBBON.length}>{r}</li>
          ))}
        </ul>
      </div>
    </section>
  );
};

const Benefits: React.FC = () => (
  <section className="h-section" id="features">
    <div className="h-container">
      <header className="h-head">
        <Eyebrow>Why choose us</Eyebrow>
        <h2>Benefits of Using Hishobkr</h2>
        <p>
          One app for the counter, the floor and the kitchen. Built for Indian restaurants, cafés and
          cloud kitchens that cannot afford to stop billing.
        </p>
      </header>

      <div className="h-benefits">
        <div className="h-benefit-col">
          {BENEFITS_LEFT.map((b) => (
            <article className="h-card" key={b.title}>
              <span className="h-icon"><b.icon size={22} aria-hidden="true" /></span>
              <h3>{b.title}</h3>
              <p>{b.text}</p>
            </article>
          ))}
        </div>
        <Phone src="/images/app/more.png" alt="Hishobkr restaurant operations screen" className="is-feature" />
        <div className="h-benefit-col">
          {BENEFITS_RIGHT.map((b) => (
            <article className="h-card" key={b.title}>
              <span className="h-icon"><b.icon size={22} aria-hidden="true" /></span>
              <h3>{b.title}</h3>
              <p>{b.text}</p>
            </article>
          ))}
        </div>
      </div>
    </div>
  </section>
);

const Steps: React.FC = () => (
  <section className="h-section h-section-tint" id="how-it-works">
    <div className="h-container">
      <header className="h-head">
        <Eyebrow>How it works</Eyebrow>
        <h2>From Setup to First Bill in a Day</h2>
        <p>Four simple steps to run your whole restaurant from one app, at your own pace.</p>
      </header>

      <ol className="h-steps">
        {STEPS.map((s, i) => (
          <li className={`h-step ${i % 2 ? 'is-flipped' : ''}`} key={s.title}>
            <div className="h-step-copy">
              <span className="h-step-num">{String(i + 1).padStart(2, '0')}</span>
              <h3>{i + 1}. {s.title}</h3>
              <p>{s.text}</p>
              <ul>
                {s.points.map((p) => (
                  <li key={p}><Check size={16} aria-hidden="true" /> {p}</li>
                ))}
              </ul>
            </div>
            <div className="h-step-visual">
              <div className="h-step-blob" aria-hidden="true" />
              <Phone src={s.img} alt={s.alt} className="is-step" />
              <span className="h-chip">{s.chip}</span>
            </div>
          </li>
        ))}
      </ol>
    </div>
  </section>
);

const Devices: React.FC = () => (
  <section className="h-section h-devices" id="hardware">
    <div className="h-container">
      <header className="h-head">
        <Eyebrow>Hardware</Eyebrow>
        <h2>Works With the Devices You Have</h2>
        <p>Print 58mm and 80mm receipts and KOTs on the printer you already own. No special hardware needed.</p>
      </header>
      <ul className="h-device-row">
        {DEVICES.map((d) => (
          <li key={d.label}>
            <d.icon size={20} aria-hidden="true" />
            {d.label}
          </li>
        ))}
      </ul>
    </div>
  </section>
);

const CtaBand: React.FC = () => {
  const { navigate } = useRouter();
  return (
    <section className="h-cta">
      <div className="h-container h-cta-inner">
        <div className="h-cta-copy">
          <Eyebrow>Get started</Eyebrow>
          <h2>Start Billing Smarter Today</h2>
          <p>
            Try every feature free for {PLAN.trialDays} days. Then {PLAN.priceLabel}/{PLAN.period} for up to{' '}
            {PLAN.maxOutlets} outlets and {PLAN.maxStaff} staff.
          </p>
          <div className="h-cta-cards">
            <a className="h-cta-card" href={PLAY_STORE_URL} target="_blank" rel="noopener noreferrer">
              <span className="h-cta-card-icon"><PlayIcon /></span>
              <strong>For Android</strong>
              <small>Get it on Google Play</small>
            </a>
            <a className="h-cta-card" href={APP_STORE_URL} target="_blank" rel="noopener noreferrer">
              <span className="h-cta-card-icon"><AppleIcon /></span>
              <strong>For iPhone & iPad</strong>
              <small>Download on the App Store</small>
            </a>
            <a className="h-cta-card" href={WEB_APP_URL}>
              <span className="h-cta-card-icon"><Globe size={20} aria-hidden="true" /></span>
              <strong>For Any Browser</strong>
              <small>Open the web app</small>
            </a>
            <button type="button" className="h-cta-card is-solid" onClick={() => navigate(REGISTER_PATH)}>
              <span className="h-cta-card-icon"><ArrowRight size={20} aria-hidden="true" /></span>
              <strong>Free {PLAN.trialDays}-day trial</strong>
              <small>No card needed</small>
            </button>
          </div>
        </div>
        <div className="h-cta-visual">
          <div className="h-hero-sun is-small" aria-hidden="true" />
          <Phone src="/images/app/tables.png" alt="Hishobkr tables screen" className="is-cta-back" />
          <Phone src="/images/app/pos.png" alt="Hishobkr POS screen" className="is-cta" />
        </div>
      </div>
    </section>
  );
};

const Contact: React.FC = () => {
  const [form, setForm] = useState({ restaurant_name: '', contact_name: '', phone: '', city: '' });
  const [state, setState] = useState<'idle' | 'sending' | 'done' | 'error'>('idle');
  const set = (k: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement>) =>
    setForm((f) => ({ ...f, [k]: e.target.value }));

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setState('sending');
    try {
      await createLead({ ...form, source: 'landing-contact', plan_interest: PLAN.code });
      setState('done');
    } catch {
      setState('error');
    }
  };

  return (
    <section className="h-section" id="contact">
      <div className="h-container">
        <header className="h-head">
          <Eyebrow>Contact</Eyebrow>
          <h2>Talk to Our Team</h2>
          <p>Share your details and we will call you back to set up your restaurant.</p>
        </header>
        <div className="h-contact">
          <aside className="h-contact-info">
            {WHATSAPP_NUMBER && (
              <a className="h-contact-item" href={`https://wa.me/${WHATSAPP_NUMBER}`} target="_blank" rel="noopener noreferrer">
                <span className="h-icon is-light"><WhatsAppIcon /></span>
                <span><strong>Chat on WhatsApp</strong><small>+91 80554 95055</small></span>
              </a>
            )}
            <a className="h-contact-item" href={`mailto:${SUPPORT_EMAIL}`}>
              <span className="h-icon is-light"><Mail size={20} aria-hidden="true" /></span>
              <span><strong>Email us</strong><small>{SUPPORT_EMAIL}</small></span>
            </a>
            <a className="h-contact-item" href={WEB_APP_URL}>
              <span className="h-icon is-light"><QrCode size={20} aria-hidden="true" /></span>
              <span><strong>Already a customer?</strong><small>Log in to the web app</small></span>
            </a>
          </aside>

          <form className="h-form" onSubmit={submit}>
            {state === 'done' ? (
              <p className="h-form-done">Thanks! We will reach out to you shortly.</p>
            ) : (
              <>
                <div className="h-form-grid">
                  <label>Restaurant name<input required value={form.restaurant_name} onChange={set('restaurant_name')} /></label>
                  <label>Your name<input value={form.contact_name} onChange={set('contact_name')} /></label>
                  <label>Mobile number<input required type="tel" inputMode="tel" pattern="[0-9+ ]{10,15}" value={form.phone} onChange={set('phone')} /></label>
                  <label>City<input value={form.city} onChange={set('city')} /></label>
                </div>
                {state === 'error' && <p className="h-form-error">Could not send right now. Please email {SUPPORT_EMAIL}.</p>}
                <button className="h-btn" type="submit" disabled={state === 'sending'}>
                  {state === 'sending' ? 'Sending…' : 'Request a callback'} <ArrowRight size={16} aria-hidden="true" />
                </button>
              </>
            )}
          </form>
        </div>
      </div>
    </section>
  );
};

export const HomePage: React.FC<HomePageProps> = ({ onOpenDemo }) => (
  <main className="h-page">
    <Hero onOpenDemo={() => onOpenDemo()} />
    <Benefits />
    <Steps />
    <Devices />
    <CtaBand />
    <Pricing />
    <FAQ />
    <Contact />
    {WHATSAPP_NUMBER && (
      <a
        className="h-wa-float"
        href={`https://wa.me/${WHATSAPP_NUMBER}?text=${encodeURIComponent('Hi, I want to know more about Hishobkr')}`}
        target="_blank"
        rel="noopener noreferrer"
        aria-label="Chat with us on WhatsApp"
      >
        <WhatsAppIcon size={28} />
      </a>
    )}
  </main>
);
