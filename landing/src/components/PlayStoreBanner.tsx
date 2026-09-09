import React from 'react';
import { Tablet, Monitor, Printer, QrCode } from 'lucide-react';

export const PlayStoreBanner: React.FC = () => {
  return (
    <section className="section" style={{ padding: '40px 0' }}>
      <div className="container">
        <div className="playstore-banner">
          <div className="playstore-grid">
            <div>
              <span className="hero-pill-badge" style={{ backgroundColor: 'rgba(255,255,255,0.15)', color: '#FFFFFF', borderColor: 'rgba(255,255,255,0.25)', marginBottom: '16px', display: 'inline-block' }}>
                HARDWARE AGNOSTIC ARCHITECTURE
              </span>
              <h2 className="playstore-title">
                Deploy on Any Android Tablet or Windows Desktop
              </h2>
              <p className="playstore-desc">
                No expensive proprietary hardware lock-in. Run FoodPOS on readily available commercial Android tablets (8&quot; to 12&quot;) for captains, or Windows desktop billing counters with instant USB/Bluetooth thermal printer connectivity.
              </p>

              <div className="playstore-badges">
                <a
                  href="#playstore"
                  className="badge-button"
                  onClick={(e) => {
                    e.preventDefault();
                    alert('FoodPOS is currently rolling out on Google Play Console. Download demo APK or schedule onboarding.');
                  }}
                >
                  <Tablet size={22} />
                  <div style={{ textAlign: 'left' }}>
                    <div style={{ fontSize: '0.7rem', textTransform: 'uppercase' }}>Available on</div>
                    <div style={{ fontSize: '1rem', fontWeight: 700 }}>Google Play</div>
                  </div>
                </a>

                <a
                  href="#windows"
                  className="badge-button"
                  onClick={(e) => {
                    e.preventDefault();
                    alert('Windows Desktop installer available for onboarding partners.');
                  }}
                >
                  <Monitor size={22} />
                  <div style={{ textAlign: 'left' }}>
                    <div style={{ fontSize: '0.7rem', textTransform: 'uppercase' }}>Download for</div>
                    <div style={{ fontSize: '1rem', fontWeight: 700 }}>Windows PC</div>
                  </div>
                </a>
              </div>
            </div>

            {/* Device Compatibility Matrix */}
            <div className="playstore-device-mock">
              <div style={{ fontSize: '0.85rem', fontWeight: 700, letterSpacing: '0.05em', color: '#D6C7B7', textTransform: 'uppercase' }}>
                Tested Peripheral Ecosystem
              </div>

              <div className="device-row">
                <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                  <Printer size={18} style={{ color: 'var(--spice-ochre)' }} />
                  <span>58mm & 80mm ESC/POS Thermal Printers</span>
                </div>
                <span style={{ fontSize: '0.75rem', color: '#85E3B3', fontWeight: 700 }}>USB • BT • LAN</span>
              </div>

              <div className="device-row">
                <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                  <Tablet size={18} style={{ color: 'var(--terracotta)' }} />
                  <span>Android OS Tablets (8&quot;, 10&quot;, 12&quot;)</span>
                </div>
                <span style={{ fontSize: '0.75rem', color: '#85E3B3', fontWeight: 700 }}>Android 9.0+</span>
              </div>

              <div className="device-row">
                <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                  <QrCode size={18} style={{ color: '#E28743' }} />
                  <span>Handheld USB 2D Barcode Scanners</span>
                </div>
                <span style={{ fontSize: '0.75rem', color: '#85E3B3', fontWeight: 700 }}>Plug & Play</span>
              </div>

              <div className="device-row">
                <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                  <Monitor size={18} style={{ color: '#85E3B3' }} />
                  <span>Kitchen Display Monitors & TVs</span>
                </div>
                <span style={{ fontSize: '0.75rem', color: '#85E3B3', fontWeight: 700 }}>Web KDS Ready</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};
