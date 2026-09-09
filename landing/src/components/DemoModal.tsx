import React, { useState } from 'react';
import { X, Sparkles, CheckCircle2, MessageCircle, ArrowRight } from 'lucide-react';

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
  const [demoId, setDemoId] = useState('');

  if (!isOpen) return null;

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!restaurantName || !phone) return;

    const randomId = `DEMO-${Math.floor(1000 + Math.random() * 9000)}`;
    setDemoId(randomId);
    setSubmitted(true);
  };

  const handleReset = () => {
    setSubmitted(false);
    setRestaurantName('');
    setContactName('');
    setPhone('');
    onClose();
  };

  const whatsappMessage = encodeURIComponent(
    `Hi FoodPOS Team! I would like to schedule a 15-minute live demo.\n\nRestaurant: ${restaurantName}\nCity: ${city}\nContact: ${contactName}\nPhone: ${phone}\nFormat: ${outletFormat}\nTicket: ${demoId || 'NEW'}`
  );

  return (
    <div className="modal-overlay" onClick={handleReset}>
      <div className="modal-content" onClick={(e) => e.stopPropagation()}>
        <button onClick={handleReset} className="modal-close-btn">
          <X size={18} />
        </button>

        {!submitted ? (
          <div>
            <span className="hero-pill-badge" style={{ marginBottom: '12px', display: 'inline-block' }}>
              15-MIN PERSONALIZED WALKTHROUGH
            </span>
            <h3 className="modal-title">Book a Live FoodPOS Demo</h3>
            <p className="modal-subtitle">
              See how FoodPOS operates offline, handles rush-hour KOTs, and balances your drawer.
              {defaultPlan && (
                <span style={{ color: 'var(--terracotta)', fontWeight: 600 }}>
                  {' '}Selected interest: {defaultPlan} Plan.
                </span>
              )}
            </p>

            <form onSubmit={handleSubmit}>
              <div className="form-group">
                <label className="form-label">Restaurant / Café Name *</label>
                <input
                  type="text"
                  required
                  placeholder="e.g. Royal Biryani &amp; Kebabs"
                  className="form-input"
                  value={restaurantName}
                  onChange={(e) => setRestaurantName(e.target.value)}
                />
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '14px' }}>
                <div className="form-group">
                  <label className="form-label">City *</label>
                  <select
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
                  <label className="form-label">Outlet Format</label>
                  <select
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

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '14px' }}>
                <div className="form-group">
                  <label className="form-label">Owner / Manager Name</label>
                  <input
                    type="text"
                    placeholder="e.g. Satyajit"
                    className="form-input"
                    value={contactName}
                    onChange={(e) => setContactName(e.target.value)}
                  />
                </div>

                <div className="form-group">
                  <label className="form-label">WhatsApp Mobile Number *</label>
                  <input
                    type="tel"
                    required
                    placeholder="e.g. 98220 00000"
                    className="form-input"
                    value={phone}
                    onChange={(e) => setPhone(e.target.value)}
                  />
                </div>
              </div>

              <button
                type="submit"
                className="btn btn-primary"
                style={{ width: '100%', marginTop: '12px', padding: '14px' }}
              >
                <Sparkles size={18} /> Confirm Demo Request
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
              Demo Request Confirmed!
            </h3>
            <p style={{ color: 'var(--text-muted)', fontSize: '0.95rem', marginBottom: '20px' }}>
              Thank you, <strong>{contactName || restaurantName}</strong>! Your demo reference code is{' '}
              <span style={{ fontWeight: 700, color: 'var(--text-espresso)' }}>{demoId}</span>.
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
              <div style={{ marginTop: '8px', color: 'var(--emerald-herbal)', fontWeight: 600 }}>
                ✓ An onboarding specialist will contact you within 2 business hours.
              </div>
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
              <a
                href={`https://wa.me/919822000000?text=${whatsappMessage}`}
                target="_blank"
                rel="noopener noreferrer"
                className="btn btn-whatsapp"
                style={{ width: '100%' }}
              >
                <MessageCircle size={18} /> Chat with Specialist on WhatsApp Now <ArrowRight size={16} />
              </a>

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
