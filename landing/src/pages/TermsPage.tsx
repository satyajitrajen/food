import React from 'react';
import { useRouter } from '../router';
import { ArrowLeft } from 'lucide-react';

export const TermsPage: React.FC = () => {
  const { navigate } = useRouter();

  return (
    <div className="policy-page container">
      <button onClick={() => navigate('/')} className="btn btn-secondary" style={{ marginBottom: '28px' }}>
        <ArrowLeft size={16} /> Back to FoodPOS Home
      </button>

      <div className="policy-header">
        <span className="section-eyebrow">Legal Agreement</span>
        <h1>Terms of Service</h1>
        <div className="policy-meta">
          <strong>Effective Date:</strong> September 9, 2026 • <strong>Version:</strong> 1.2
        </div>
      </div>

      <div className="policy-body">
        <p>
          These Terms of Service (&ldquo;Terms&rdquo;) constitute a binding agreement between you (&ldquo;Customer&rdquo;, &ldquo;Merchant&rdquo;, or &ldquo;User&rdquo;) and <strong>FoodPOS</strong> governing access to and use of our Point-of-Sale software, tablet applications, and cloud services.
        </p>

        <h2>1. License & Scope of Service</h2>
        <p>
          Subject to your subscription tier, FoodPOS grants you a non-exclusive, non-transferable, revocable license to install and operate the FoodPOS application on authorized terminals (Android tablets, Windows desktop devices, or kitchen displays) within the specified restaurant outlets.
        </p>

        <h2>2. Merchant Responsibilities</h2>
        <p>As a FoodPOS merchant, you agree to:</p>
        <ul>
          <li>Maintain confidential PINs and master credentials for your staff roles.</li>
          <li>Ensure accurate tax rates (GSTIN, CGST/SGST/IGST percentages) configured for your food and beverage menu items.</li>
          <li>Comply with local FSSAI packaging, licensing, and hygiene standards.</li>
          <li>Accurately declare daily cash drawer balances during shift open and closing reconciliation.</li>
        </ul>

        <h2>3. Offline Durability & Cloud Synchronization</h2>
        <p>
          FoodPOS is engineered to operate seamlessly during network failures using a local outbox. However, Merchants are responsible for ensuring that terminals are periodically connected to a functional internet connection to synchronize offline transaction queues, update tax catalogs, and maintain cloud backups.
        </p>

        <h2>4. Hardware Compatibility</h2>
        <p>
          FoodPOS works with standard ESC/POS thermal receipt printers (USB, Bluetooth, and LAN) and Android tablets running Android 9.0 (Pie) or higher. While we test extensively with popular printer brands (Epson, TVS, NGX, Posiflex), FoodPOS is not responsible for physical hardware failure or cabling malfunctions on site.
        </p>

        <h2>5. Subscription, Billing & Renewals</h2>
        <p>
          Paid plans are billed in advance on a monthly or annual cycle in Indian Rupees (INR). Unless cancelled before the renewal date, subscriptions automatically renew. Tax invoices with proper input tax credit (ITC) are issued upon payment.
        </p>

        <h2>6. Limitation of Liability</h2>
        <p>
          To the maximum extent permitted by Indian law, FoodPOS shall not be liable for indirect, incidental, or consequential damages arising from hardware downtime, kitchen delays, or power failures at the merchant&apos;s physical premises.
        </p>

        <h2>7. Governing Law & Dispute Resolution</h2>
        <p>
          These Terms are governed by and construed in accordance with the laws of the Republic of India. Any disputes arising hereunder shall be subject to the exclusive jurisdiction of the competent courts in Pune, Maharashtra.
        </p>

        <h2>8. Contact Legal Support</h2>
        <p>
          For legal inquiries or notices, reach out to <a href="mailto:legal@foodpos.app" style={{ color: 'var(--terracotta)', fontWeight: 600 }}>legal@foodpos.app</a>.
        </p>
      </div>
    </div>
  );
};
