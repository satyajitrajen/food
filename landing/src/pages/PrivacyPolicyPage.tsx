import React from 'react';
import { useRouter } from '../router';
import { ArrowLeft, ShieldCheck, Database } from 'lucide-react';

export const PrivacyPolicyPage: React.FC = () => {
  const { navigate } = useRouter();

  return (
    <div className="policy-page container">
      <button onClick={() => navigate('/')} className="btn btn-secondary" style={{ marginBottom: '28px' }}>
        <ArrowLeft size={16} /> Back to Hishobkr Home
      </button>

      <div className="policy-header">
        <span className="section-eyebrow">Google Play Developer Compliance</span>
        <h1>Privacy Policy for Hishobkr</h1>
        <div className="policy-meta">
          <strong>Effective Date:</strong> September 9, 2026 • <strong>Last Updated:</strong> September 9, 2026
        </div>
      </div>

      <div className="policy-body">
        <p>
          Welcome to <strong>Hishobkr</strong> (&ldquo;Hishobkr&rdquo;, &ldquo;we&rdquo;, &ldquo;our&rdquo;, or &ldquo;us&rdquo;). We are committed to protecting the privacy, confidentiality, and data integrity of restaurant owners, food service operators, waitstaff, and their dining patrons.
        </p>

        <p>
          This Privacy Policy governs the use of the Hishobkr Android Application, Desktop App, and related cloud synchronization services. It discloses what information we collect, how it is processed and stored on your local devices and cloud servers, and your statutory rights.
        </p>

        <div className="policy-box">
          <ShieldCheck size={24} style={{ color: 'var(--emerald-herbal)', marginBottom: '8px' }} />
          <h4>Privacy Promise</h4>
          <p style={{ margin: 0, fontSize: '0.95rem' }}>
            Hishobkr does not sell, rent, or monetize your restaurant&apos;s customer lists, sales records, or billing information to third-party advertisers or data brokers.
          </p>
        </div>

        <h2>1. Information We Collect</h2>

        <h3>A. Restaurant Account & Staff Profile Data</h3>
        <p>
          When setting up an outlet on Hishobkr, we collect business registration details such as Restaurant Name, Trade Name, Outlet Address, GSTIN (optional for unregistered entities), and FSSAI license numbers.
        </p>
        <p>
          For operational authentication, staff profiles include staff names, role assignments (Admin, Manager, Cashier, Waiter, Kitchen), and 4-to-6 digit access PINs. <strong>All staff PINs are salted and hashed using bcrypt before local storage or cloud transmission.</strong>
        </p>

        <h3>B. Dine-in Patron & Customer Data</h3>
        <p>
          When punching orders, staff may enter a patron&apos;s 10-digit mobile number to:
        </p>
        <ul>
          <li>Dispatch digital bills via WhatsApp or SMS.</li>
          <li>Track repeat visits, lifetime spend, and store credit.</li>
        </ul>
        <p>Patron phone numbers are collected solely for the restaurant&apos;s direct billing records and customer service.</p>

        <h3>C. Transactional & Operational Records</h3>
        <p>
          Hishobkr stores line-item order details, table numbers, KOT timestamps, payment methods (Cash, UPI, Card), discount authorizations, shift opening/closing cash counts, petty cash expenses, and inventory adjustments.
        </p>

        <h2>2. Android Device Permissions & System Features</h2>
        <p>Hishobkr requests specific Android permissions strictly to execute its POS and billing duties:</p>

        <ul>
          <li>
            <strong>INTERNET & ACCESS_NETWORK_STATE:</strong> Needed to sync offline order queues to the cloud backend when connectivity is detected, receive live KOT updates, and print to network (LAN/Wi-Fi) receipt printers.
          </li>
          <li>
            <strong>POST_NOTIFICATIONS & VIBRATE:</strong> Used to alert staff about new KOTs and orders that are ready to serve.
          </li>
          <li>
            <strong>RECEIVE_BOOT_COMPLETED:</strong> Used only to restore scheduled notifications after the device restarts.
          </li>
          <li>
            <strong>Photos (optional):</strong> If you choose to add a photo to a menu item, the system photo picker is used. Hishobkr does not request broad access to your storage.
          </li>
        </ul>

        <h2>3. Offline-First Architecture & Data Durability</h2>
        <div className="policy-box">
          <Database size={24} style={{ color: 'var(--brand-primary)', marginBottom: '8px' }} />
          <h4>Local Device Storage</h4>
          <p style={{ margin: 0, fontSize: '0.95rem' }}>
            To withstand Indian broadband and power outages, Hishobkr persists your operational data to the app&apos;s private storage on the device. When offline, transactions queue safely on the device and automatically sync via idempotent requests once a network connection is re-established.
          </p>
        </div>

        <h2>4. Data Retention & Statutory Accounting</h2>
        <p>
          In accordance with Indian tax regulations (CGST & SGST Rules), detailed tax invoice records, credit notes, and shift Z-reports are retained for a minimum statutory period of 72 months (6 years). Temporary offline sync queues are purged immediately once cloud acknowledgement is confirmed.
        </p>

        <h2>5. Your Rights & Data Deletion Requests</h2>
        <p>
          Restaurant administrators have the right to inspect, correct, and export their data, and to close their account at any time from Settings in the app or by email request. When an account is closed, sign-in is disabled immediately and personal data is removed: owner and staff names, email addresses, mobile numbers, PINs and passwords are erased, customer contact details are erased, and push notification tokens and active sessions are revoked. Orders and tax invoices are not deleted, because Indian GST law requires them to be kept for the statutory period described in Section 4; they are retained in anonymised form and no longer identify any person. For full details, visit our dedicated <a href="#/data-deletion" onClick={(e) => { e.preventDefault(); navigate('/data-deletion'); }} style={{ color: 'var(--brand-primary)', fontWeight: 600, textDecoration: 'underline' }}>Account & Data Deletion Portal</a>.
        </p>

        <h2>6. Security Measures</h2>
        <p>
          We employ industry-standard security protocols:
        </p>
        <ul>
          <li>TLS (HTTPS) encryption for all data in transit between the app and our servers.</li>
          <li>Role-based access control with manager-PIN verification gates for refunds, voids, and discounts.</li>
        </ul>

        <h2>7. Contact Our Privacy Officer</h2>
        <p>If you have any questions, concerns, or requests regarding this Privacy Policy, contact us at:</p>
        <p>
          <strong>Hishobkr Data Governance Team</strong><br />
          Email: <a href="mailto:support@hishobkr.com" style={{ color: 'var(--brand-primary)' }}>support@hishobkr.com</a><br />
          Location: Pune, Maharashtra, India
        </p>
      </div>
    </div>
  );
};
