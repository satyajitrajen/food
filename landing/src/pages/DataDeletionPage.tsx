import React from 'react';
import { useRouter } from '../router';
import { ArrowLeft, Mail, AlertTriangle } from 'lucide-react';

export const DataDeletionPage: React.FC = () => {
  const { navigate } = useRouter();

  return (
    <div className="policy-page container">
      <button onClick={() => navigate('/')} className="btn btn-secondary" style={{ marginBottom: '28px' }}>
        <ArrowLeft size={16} /> Back to Hishobkr Home
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
          At Hishobkr, we respect your right to control your personal and business data. Under Google Play&apos;s User Data policy and applicable data privacy regulations, Hishobkr provides a simple, direct mechanism for restaurant owners, staff members, and customers to request complete deletion of their accounts and associated personal data.
        </p>

        <h2>1. How to Request Account & Data Deletion</h2>
        <p>
          Restaurant owners can close their account directly in the app: open <strong>Settings</strong>, choose <strong>Delete account</strong>, enter your owner email and password, and type DELETE to confirm. The account is closed immediately.
        </p>
        <p>You can also request deletion by email:</p>

        <div className="policy-box">
          <h3 style={{ marginTop: 0, display: 'flex', alignItems: 'center', gap: '8px' }}>
            <Mail size={20} style={{ color: 'var(--brand-primary)' }} />
            Email Request
          </h3>
          <p>
            Send an email from your registered restaurant admin email address to:
          </p>
          <p style={{ fontSize: '1.1rem', fontWeight: 700, color: 'var(--brand-primary)' }}>
            <a href="mailto:support@hishobkr.com?subject=Account%20and%20Data%20Deletion%20Request">support@hishobkr.com</a>
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

        <h2>2. What Happens to Your Data</h2>
        <p>When an account is closed, sign-in is disabled and the following personal data is erased:</p>
        <ul>
          <li><strong>Owner Account:</strong> Name, email address, and password are erased, and the organization name and GSTIN are removed.</li>
          <li><strong>Staff Records:</strong> Staff names, mobile numbers, photos, and PINs are erased, and staff logins are disabled.</li>
          <li><strong>Customer Directory:</strong> Customer names, phone numbers, email addresses, postal addresses, GSTINs, and notes are erased.</li>
          <li><strong>Device Tokens & Sessions:</strong> Push notification tokens are deleted and all active sessions are revoked.</li>
        </ul>
        <p>Orders, tax invoices, and your menu catalog are not deleted. They are kept in anonymised form so that the records required by law (see below) remain intact, but they no longer identify you, your staff, or your customers.</p>

        <h2>3. Data Retention Exceptions (Statutory Tax Compliance)</h2>
        <div className="policy-box" style={{ borderLeftColor: 'var(--color-warning)' }}>
          <AlertTriangle size={24} style={{ color: 'var(--color-warning)', marginBottom: '8px' }} />
          <h4>Statutory Invoicing Retention Notice</h4>
          <p style={{ margin: 0, fontSize: '0.95rem' }}>
            Under Section 36 of the Central Goods and Services Tax (CGST) Act, 2017, registered businesses are legally obligated to maintain tax invoices, credit notes, and annual financial turnover records for a mandatory statutory period (up to 72 months). 
          </p>
          <p style={{ marginTop: '8px', fontSize: '0.95rem' }}>
            Consequently, financial ledger entries and finalized GST invoices are retained in anonymised form (stripped of personal names and contact details) for the statutory period.
          </p>
        </div>

        <h2>4. Turnaround Time & Confirmation</h2>
        <p>
          Deletion from within the app takes effect immediately. For email requests, we will confirm receipt within <strong>24 business hours</strong> and close the account within <strong>48 hours</strong> of verifying your request, then confirm by email.
        </p>

        <h2>5. Contact Us</h2>
        <p>
          For urgent queries regarding data protection, contact our Data Protection Officer at <a href="mailto:support@hishobkr.com" style={{ color: 'var(--brand-primary)', fontWeight: 600 }}>support@hishobkr.com</a>.
        </p>
      </div>
    </div>
  );
};
