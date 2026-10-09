import React, { useEffect, useRef, useState } from 'react';
import { X, Sparkles, CheckCircle2, MessageCircle, ArrowRight, Loader2, Mail } from 'lucide-react';
import { WHATSAPP_NUMBER, SUPPORT_EMAIL, createLead } from '../console/api';

interface DemoModalProps {
  isOpen: boolean;
  onClose: () => void;
  defaultPlan?: string;
}

export const DemoModal: React.FC<DemoModalProps> = ({ isOpen, onClose, defaultPlan }) => {
  const [restaurantName, setRestaurantName] = useState('');
  const [city, setCity] = useState('Pune');
  const [contactName, setContactName] = useState('');
  const [phone, setPhone] = useState('');
  const [outletFormat, setOutletFormat] = useState('Dine-in Restaurant');
  const [submitted, setSubmitted] = useState(false);
  const [saved, setSaved] = useState(true);
  const [demoId, setDemoId] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [formError, setFormError] = useState('');

  const firstFieldRef = useRef<HTMLInputElement>(null);
  const prevFocus = useRef<HTMLElement | null>(null);

  // Focus the first field on open, return focus to the trigger on close.
  useEffect(() => {
    if (!isOpen) return;
    prevFocus.current = document.activeElement as HTMLElement | null;
    const timer = window.setTimeout(() => firstFieldRef.current?.focus(), 0);
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        handleReset();
      }
    };
    document.addEventListener('keydown', onKey);
    return () => {
      window.clearTimeout(timer);
      document.removeEventListener('keydown', onKey);
      prevFocus.current?.focus?.();
    };
  }, [isOpen]);

  if (!isOpen) return null;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setFormError('');
    const digits = phone.replace(/\D/g, '');
    if (restaurantName.trim().length < 2) {
      setFormError('Enter your restaurant or café name so we know who to reach.');
      firstFieldRef.current?.focus();
      return;
    }
    if (digits.length < 10 || digits.length > 12) {
      setFormError('Enter a valid 10-digit WhatsApp mobile number so we can contact you.');
      return;
    }
    setSubmitting(true);
    // No reference is shown when the API is unreachable — the WhatsApp
    // button below still gets the lead to a human.
    let ref = '';
    let ok = false;
    try {
      const res = await createLead({
        restaurant_name: restaurantName.trim(),
        contact_name: contactName.trim(),
        phone: digits,
        city,
        outlet_format: outletFormat,
        plan_interest: defaultPlan ?? '',
        source: 'landing-demo',
      });
      if (res && typeof res.id === 'string') ref = res.id;
      ok = true;
    } catch {
      ok = false;
    }
    setDemoId(ref);
    setSaved(ok);
    setSubmitting(false);
    setSubmitted(true);
  };

  const handleReset = () => {
    setSubmitted(false);
    setSaved(true);
    setRestaurantName('');
    setContactName('');
    setPhone('');
    setFormError('');
    setSubmitting(false);
    onClose();
  };

  const whatsappMessage = encodeURIComponent(
    `Hi Hishobkr team! I would like to schedule a 15-minute live demo.\n\nRestaurant: ${restaurantName}\nCity: ${city}\nContact: ${contactName}\nPhone: ${phone}\nFormat: ${outletFormat}${demoId ? `\nReference: ${demoId}` : ''}`
  );

  return (
    <div className="modal-overlay" onClick={handleReset}>
      <div
        className="modal-content"
        role="dialog"
        aria-modal="true"
        aria-labelledby="demo-modal-title"
        onClick={(e) => e.stopPropagation()}
      >
        <button onClick={handleReset} className="modal-close-btn" aria-label="Close demo form">
          <X size={18} />
        </button>

        {!submitted ? (
          <div>
            <span className="hero-pill-badge" style={{ marginBottom: '12px', display: 'inline-block' }}>
              15-MIN PERSONALIZED WALKTHROUGH
            </span>
            <h3 className="modal-title" id="demo-modal-title">Book a Hishobkr Demo</h3>
            <p className="modal-subtitle">
              See how Hishobkr works offline, handles rush-hour KOTs, and closes a shift with a blind cash count.
              {defaultPlan && (
                <span style={{ color: 'var(--brand-primary)', fontWeight: 600 }}>
                  {' '}Selected interest: {defaultPlan} Plan.
                </span>
              )}
            </p>

            {formError && (
              <p role="alert" className="form-error" style={{ marginBottom: '10px' }}>
                {formError}
              </p>
            )}

            <form onSubmit={handleSubmit} noValidate>
              <div className="form-group">
                <label className="form-label" htmlFor="demo-restaurant">Restaurant / Café Name *</label>
                <input
                  id="demo-restaurant"
                  ref={firstFieldRef}
                  type="text"
                  required
                  placeholder="e.g. Royal Biryani & Kebabs"
                  className="form-input"
                  value={restaurantName}
                  aria-invalid={formError.includes('restaurant')}
                  onChange={(e) => setRestaurantName(e.target.value)}
                />
              </div>

              <div className="demo-form-row">
                <div className="form-group">
                  <label className="form-label" htmlFor="demo-city">City *</label>
                  <select
                    id="demo-city"
                    className="form-select"
                    value={city}
                    onChange={(e) => setCity(e.target.value)}
                  >
                    <option value="Pune">Pune</option>
                    <option value="Mumbai">Mumbai</option>
                    <option value="Bengaluru">Bengaluru</option>
                    <option value="Delhi NCR">Delhi NCR</option>
                    <option value="Hyderabad">Hyderabad</option>
                    <option value="Chennai">Chennai</option>
                    <option value="Kolkata">Kolkata</option>
                    <option value="Other">Other City</option>
                  </select>
                </div>

                <div className="form-group">
                  <label className="form-label" htmlFor="demo-format">Outlet Format</label>
                  <select
                    id="demo-format"
                    className="form-select"
                    value={outletFormat}
                    onChange={(e) => setOutletFormat(e.target.value)}
                  >
                    <option value="Dine-in Restaurant">Dine-in Restaurant</option>
                    <option value="Café / QSR">Café / QSR Kiosk</option>
                    <option value="Cloud Kitchen">Cloud Kitchen</option>
                    <option value="Restro-Bar / Brewery">Restro-Bar / Brewery</option>
                  </select>
                </div>
              </div>

              <div className="demo-form-row">
                <div className="form-group">
                  <label className="form-label" htmlFor="demo-contact">Owner / Manager Name</label>
                  <input
                    id="demo-contact"
                    type="text"
                    autoComplete="name"
                    placeholder="e.g. Satyajit"
                    className="form-input"
                    value={contactName}
                    onChange={(e) => setContactName(e.target.value)}
                  />
                </div>

                <div className="form-group">
                  <label className="form-label" htmlFor="demo-phone">WhatsApp Mobile Number *</label>
                  <input
                    id="demo-phone"
                    type="tel"
                    required
                    inputMode="tel"
                    autoComplete="tel"
                    placeholder="e.g. 98220 00000"
                    className="form-input"
                    value={phone}
                    aria-invalid={formError.includes('number')}
                    onChange={(e) => setPhone(e.target.value)}
                  />
                </div>
              </div>

              <button
                type="submit"
                className="btn btn-primary"
                style={{ width: '100%', marginTop: '12px', padding: '14px' }}
                disabled={submitting}
              >
                {submitting ? (
                  <>
                    <Loader2 size={18} className="demo-spin" aria-hidden="true" /> Confirm Demo Request
                  </>
                ) : (
                  <>
                    <Sparkles size={18} /> Confirm Demo Request
                  </>
                )}
              </button>
            </form>
          </div>
        ) : (
          <div style={{ textAlign: 'center', padding: '12px 0' }}>
            <div
              style={{
                width: '64px',
                height: '64px',
                borderRadius: '50%',
                backgroundColor: 'var(--emerald-herbal-light)',
                border: '1px solid var(--emerald-herbal-border)',
                color: 'var(--emerald-herbal)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                margin: '0 auto 20px auto',
              }}
            >
              <CheckCircle2 size={36} />
            </div>

            <h3 className="modal-title" style={{ fontSize: '1.5rem' }}>
              {saved ? 'Demo request received' : 'Almost there'}
            </h3>
            <p style={{ color: 'var(--text-muted)', fontSize: '0.95rem', marginBottom: '20px' }}>
              Thank you, <strong>{contactName || restaurantName}</strong>!
              {saved && demoId && (
                <>
                  {' '}Your reference is{' '}
                  <span style={{ fontWeight: 700, color: 'var(--text-espresso)' }}>{demoId}</span>.
                </>
              )}
            </p>

            <div
              style={{
                backgroundColor: 'var(--bg-porcelain)',
                border: '1px solid var(--border-soft)',
                borderRadius: 'var(--radius-md)',
                padding: '20px',
                marginBottom: '24px',
                textAlign: 'left',
                fontSize: '0.85rem',
              }}
            >
              <div><strong>Restaurant:</strong> {restaurantName} ({city})</div>
              <div><strong>Outlet Type:</strong> {outletFormat}</div>
              <div><strong>WhatsApp:</strong> {phone}</div>
              {saved && (
                <div style={{ marginTop: '8px', color: 'var(--emerald-herbal)', fontWeight: 600 }}>
                  ✓ We&apos;ll reach out on WhatsApp to fix a time.
                </div>
              )}
            </div>

            {!saved && (
              <p role="alert" style={{ color: 'var(--non-veg-red)', fontSize: '0.85rem', marginBottom: '12px' }}>
                We couldn't save your request just now — please{' '}
                {WHATSAPP_NUMBER ? 'message us on WhatsApp below' : 'email us using the button below'} so we don't miss you.
              </p>
            )}

            <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
              {WHATSAPP_NUMBER ? (
                <a
                  href={`https://wa.me/${WHATSAPP_NUMBER}?text=${whatsappMessage}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="btn btn-whatsapp"
                  style={{ width: '100%' }}
                >
                  <MessageCircle size={18} /> Chat with us on WhatsApp <ArrowRight size={16} />
                </a>
              ) : (
                <a
                  href={`mailto:${SUPPORT_EMAIL}?subject=${encodeURIComponent('Hishobkr demo request')}&body=${whatsappMessage}`}
                  className="btn btn-primary"
                  style={{ width: '100%' }}
                >
                  <Mail size={18} /> Email us <ArrowRight size={16} />
                </a>
              )}

              <button onClick={handleReset} className="btn btn-secondary" style={{ width: '100%' }}>
                Done
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
