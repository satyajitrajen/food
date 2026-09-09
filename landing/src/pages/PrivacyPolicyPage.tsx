import React from 'react';
import { useRouter } from '../router';
import { ArrowLeft, ShieldCheck, Database } from 'lucide-react';

export const PrivacyPolicyPage: React.FC = () => {
  const { navigate } = useRouter();

  return (
    <div className="policy-page container">
      <button onClick={() => navigate('/')} className="btn btn-secondary" style={{ marginBottom: '28px' }}>
        <ArrowLeft size={16} /> Back to FoodPOS Home
      </button>

      <div className="policy-header">
        <span className="section-eyebrow">Google Play Developer Compliance</span>
        <h1>Privacy Policy for FoodPOS</h1>
        <div className="policy-meta">
          <strong>Effective Date:</strong> September 9, 2026 • <strong>Last Updated:</strong> September 9, 2026
        </div>
      </div>

      <div className="policy-body">
        <p>
          Welcome to <strong>FoodPOS</strong> (&ldquo;FoodPOS&rdquo;, &ldquo;we&rdquo;, &ldquo;our&rdquo;, or &ldquo;us&rdquo;). We are committed to protecting the privacy, confidentiality, and data integrity of restaurant owners, food service operators, waitstaff, and their dining patrons.
        </p>

        <p>
          This Privacy Policy governs the use of the FoodPOS Android Application, Desktop Terminal, and related cloud synchronization services. It discloses what information we collect, how it is processed and stored on your local devices and cloud servers, and your statutory rights.
        </p>

        <div className="policy-box">
          <ShieldCheck size={24} style={{ color: 'var(--emerald-herbal)', marginBottom: '8px' }} />
          <h4>Privacy Promise</h4>
          <p style={{ margin: 0, fontSize: '0.95rem' }}>
            FoodPOS does not sell, rent, or monetize your restaurant&apos;s customer lists, sales records, or billing information to third-party advertisers or data brokers.
          </p>
        </div>

        <h2>1. Information We Collect</h2>

        <h3>A. Restaurant Account & Staff Profile Data</h3>
        <p>
          When setting up an outlet on FoodPOS, we collect business registration details such as Restaurant Name, Trade Name, Outlet Address, GSTIN (optional for unregistered entities), and FSSAI license numbers.
        </p>
        <p>
          For operational authentication, terminal profiles include staff names, role assignments (Admin, Manager, Cashier, Waiter, Kitchen), and 4-to-6 digit access PINs. <strong>All staff PINs are salted and hashed using bcrypt before local storage or cloud transmission.</strong>
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
          FoodPOS stores line-item order details, table numbers, KOT timestamps, payment methods (Cash, UPI, Card), discount authorizations, shift opening/closing cash counts, petty cash expenses, and inventory adjustments.
        </p>

        <h2>2. Android Device Permissions & System Features</h2>
        <p>FoodPOS requests specific Android permissions strictly to execute its POS and billing duties:</p>

        <ul>
          <li>
            <strong>INTERNET & ACCESS_NETWORK_STATE:</strong> Needed to sync offline order queues to the secure cloud backend when connectivity is detected and receive live KOT updates.
          </li>
          <li>
            <strong>BLUETOOTH & BLUETOOTH_CONNECT / BLUETOOTH_SCAN:</strong> Required to pair with 58mm / 80mm wireless ESC/POS thermal receipt printers.
          </li>
          <li>
            <strong>USB_PERMISSION:</strong> Required to interface with wired USB thermal printers, handheld barcode scanners, and RJ11 cash drawers.
          </li>
          <li>
            <strong>CAMERA (Optional):</strong> Required only if you choose to scan customer loyalty QR codes or BharatQR payment codes using your device&apos;s camera.
          </li>
        </ul>

        <h2>3. Offline-First Architecture & Data Durability</h2>
        <div className="policy-box">
          <Database size={24} style={{ color: 'var(--terracotta)', marginBottom: '8px' }} />
          <h4>Local Device Storage</h4>
          <p style={{ margin: 0, fontSize: '0.95rem' }}>
            To withstand Indian broadband and power outages, FoodPOS persists your operational data to encrypted local device storage (SQLite/Hive). When offline, transactions queue safely on the device and automatically sync via idempotent requests once a network connection is re-established.
          </p>
        </div>

        <h2>4. Data Retention & Statutory Accounting</h2>
        <p>
          In accordance with Indian tax regulations (CGST & SGST Rules), detailed tax invoice records, credit notes, and shift Z-reports are retained for a minimum statutory period of 72 months (6 years). Temporary offline sync queues are purged immediately once cloud acknowledgement is confirmed.
        </p>

        <h2>5. Your Rights & Data Deletion Requests</h2>
        <p>
          Restaurant administrators have the right to inspect, correct, export, or permanently erase their accounts. For complete account closure and data deletion procedures, visit our dedicated <a href="#/data-deletion" onClick={(e) => { e.preventDefault(); navigate('/data-deletion'); }} style={{ color: 'var(--terracotta)', fontWeight: 600, textDecoration: 'underline' }}>Account & Data Deletion Portal</a>.
        </p>

        <h2>6. Security Measures</h2>
        <p>
          We employ industry-standard security protocols:
        </p>
        <ul>
          <li>End-to-end TLS 1.3 encryption for all data in transit.</li>
          <li>Role-based access control with manager-PIN verification gates for refunds, voids, and discounts.</li>
          <li>Database encryption at rest (AES-256).</li>
        </ul>

        <h2>7. Contact Our Privacy Officer</h2>
        <p>If you have any questions, concerns, or requests regarding this Privacy Policy, contact us at:</p>
        <p>
          <strong>FoodPOS Data Governance Team</strong><br />
          Email: <a href="mailto:privacy@foodpos.app" style={{ color: 'var(--terracotta)' }}>privacy@foodpos.app</a><br />
          Helpline: +91 98220 00000<br />
          Location: Pune, Maharashtra, India
        </p>
      </div>
    </div>
  );
};
