import React from 'react';
import { useRouter } from '../router';
import { ArrowLeft } from 'lucide-react';

export const RefundPolicyPage: React.FC = () => {
  const { navigate } = useRouter();

  return (
    <div className="policy-page container">
      <button onClick={() => navigate('/')} className="btn btn-secondary" style={{ marginBottom: '28px' }}>
        <ArrowLeft size={16} /> Back to FoodPOS Home
      </button>

      <div className="policy-header">
        <span className="section-eyebrow">Customer Protection</span>
        <h1>Refund & Cancellation Policy</h1>
        <div className="policy-meta">
          <strong>Effective Date:</strong> September 9, 2026
        </div>
      </div>

      <div className="policy-body">
        <p>
          At FoodPOS, our mission is to ensure every restaurant, café, and bar experiences effortless, reliable billing. We back our software subscriptions with clear, customer-friendly refund terms.
        </p>

        <h2>1. 14-Day Money-Back Guarantee (New Outlets)</h2>
        <p>
          If you are a new merchant subscribing to any paid FoodPOS plan (Starter or Pro) and find that our software does not suit your operational requirements, you may request a <strong>100% full refund within 14 calendar days</strong> of your initial activation date.
        </p>
        <p>
          No questions asked. The full subscription fee will be credited back to your original source account (UPI, Netbanking, or Card) within 5 to 7 business days.
        </p>

        <h2>2. Annual Subscription Cancellations</h2>
        <p>
          If you subscribed to an Annual Plan and need to terminate due to outlet relocation or business restructuring after the 14-day window:
        </p>
        <ul>
          <li>We will calculate the elapsed billing months at the regular monthly rate.</li>
          <li>The remaining unused balance of your annual payment will be refunded to you on a pro-rata basis.</li>
        </ul>

        <h2>3. Hardware & Peripheral Purchases</h2>
        <p>
          If you purchased bundled hardware accessories through an authorized FoodPOS partner (such as ESC/POS thermal printers, barcode scanners, or tablet stands):
        </p>
        <ul>
          <li>Hardware items in unopened, original packaging may be returned within 7 days of delivery.</li>
          <li>Defective equipment is covered under the manufacturer&apos;s 1-year replacement warranty.</li>
        </ul>

        <h2>4. How to Request a Refund</h2>
        <p>
          To process a cancellation or refund, email our accounts desk at <a href="mailto:billing@foodpos.app" style={{ color: 'var(--terracotta)', fontWeight: 600 }}>billing@foodpos.app</a> with your Outlet ID and Tax Invoice Number.
        </p>
      </div>
    </div>
  );
};
