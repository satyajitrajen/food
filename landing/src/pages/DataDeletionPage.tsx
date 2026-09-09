import React from 'react';
import { useRouter } from '../router';
import { ArrowLeft, Trash2, Mail, AlertTriangle } from 'lucide-react';

export const DataDeletionPage: React.FC = () => {
  const { navigate } = useRouter();

  return (
    <div className="policy-page container">
      <button onClick={() => navigate('/')} className="btn btn-secondary" style={{ marginBottom: '28px' }}>
        <ArrowLeft size={16} /> Back to FoodPOS Home
      </button>

      <div className="policy-header">
        <span className="section-eyebrow">Google Play User Safety Requirement</span>
        <h1>Account & Data Deletion Instructions</h1>
        <div className="policy-meta">
          <strong>Mandatory Disclosure under Google Play Console Policies</strong>
        </div>
      </div>

      <div className="policy-body">
        <p>
          At FoodPOS, we respect your right to control your personal and business data. Under Google Play&apos;s User Data policy and applicable data privacy regulations, FoodPOS provides a simple, direct mechanism for restaurant owners, staff members, and customers to request complete deletion of their accounts and associated personal data.
        </p>

        <h2>1. How to Request Account & Data Deletion</h2>
        <p>You can initiate a permanent account deletion request through either of the following methods:</p>

        <div className="policy-box">
          <h3 style={{ marginTop: 0, display: 'flex', alignItems: 'center', gap: '8px' }}>
            <Mail size={20} style={{ color: 'var(--terracotta)' }} />
            Method A: Email Request (Recommended)
          </h3>
          <p>
            Send an email from your registered restaurant admin email address to:
          </p>
          <p style={{ fontSize: '1.1rem', fontWeight: 700, color: 'var(--terracotta)' }}>
            <a href="mailto:support@foodpos.app?subject=Account%20and%20Data%20Deletion%20Request">support@foodpos.app</a>
          </p>
          <p style={{ fontSize: '0.9rem', color: 'var(--text-muted)' }}>
            Subject Line: <strong>&ldquo;Account and Data Deletion Request — [Your Restaurant Name]&rdquo;</strong><br />
            Include in the email:
          </p>
          <ul style={{ fontSize: '0.9rem', color: 'var(--text-body)' }}>
            <li>Registered Restaurant / Outlet Name</li>
            <li>Admin Phone Number or Login Identifier</li>
            <li>Reason for deletion (optional, but helps us improve)</li>
          </ul>
        </div>

        <div className="policy-box">
          <h3 style={{ marginTop: 0, display: 'flex', alignItems: 'center', gap: '8px' }}>
            <Trash2 size={20} style={{ color: 'var(--terracotta)' }} />
            Method B: In-App Terminal Erasure
          </h3>
          <p style={{ fontSize: '0.9rem', color: 'var(--text-body)' }}>
            1. Sign in to your FoodPOS terminal with the <strong>Admin Role</strong>.<br />
            2. Navigate to <strong>Settings &rarr; System & Data Governance</strong>.<br />
            3. Click <strong>&ldquo;Request Account & Data Erasure&rdquo;</strong> and enter your Admin master PIN.<br />
            4. Confirm the prompt to unbind your terminal and queue your cloud tenant for deletion.
          </p>
        </div>

        <h2>2. What Data Is Permanently Deleted</h2>
        <p>Upon verification of your request, the following data is permanently purged from our active databases and cloud storage within <strong>48 hours</strong>:</p>
        <ul>
          <li><strong>Staff Records:</strong> Staff names, login profiles, hashed PINs, and personal mobile numbers.</li>
          <li><strong>Customer Directory:</strong> Patron phone numbers, saved loyalty notes, and repeat visit logs.</li>
          <li><strong>Catalog & Menu Data:</strong> Custom categories, dish names, pricing matrices, and modifier groupings.</li>
          <li><strong>Device Tokens & Sessions:</strong> Push notification tokens, WebSocket connection IDs, and refresh tokens.</li>
        </ul>

        <h2>3. Data Retention Exceptions (Statutory Tax Compliance)</h2>
        <div className="policy-box" style={{ borderLeftColor: 'var(--spice-ochre)' }}>
          <AlertTriangle size={24} style={{ color: 'var(--spice-ochre)', marginBottom: '8px' }} />
          <h4>Statutory Invoicing Retention Notice</h4>
          <p style={{ margin: 0, fontSize: '0.95rem' }}>
            Under Section 36 of the Central Goods and Services Tax (CGST) Act, 2017, registered businesses are legally obligated to maintain tax invoices, credit notes, and annual financial turnover records for a mandatory statutory period (up to 72 months). 
          </p>
          <p style={{ marginTop: '8px', fontSize: '0.95rem' }}>
            Consequently, financial ledger entries and finalized GST invoices will be anonymized (stripped of personal names and phone numbers) and archived securely until the statutory period expires, after which they are permanently destroyed.
          </p>
        </div>

        <h2>4. Turnaround Time & Confirmation</h2>
        <p>
          Once your deletion request is received, our data governance team will confirm receipt within <strong>24 business hours</strong>. Complete deletion of eligible records is accomplished within <strong>48 hours</strong>, followed by a formal Certificate of Erasure delivered via email.
        </p>

        <h2>5. Contact Us</h2>
        <p>
          For urgent queries regarding data protection, contact our Data Protection Officer at <a href="mailto:privacy@foodpos.app" style={{ color: 'var(--terracotta)', fontWeight: 600 }}>privacy@foodpos.app</a>.
        </p>
      </div>
    </div>
  );
};
