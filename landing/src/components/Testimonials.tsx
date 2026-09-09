import React from 'react';
import { Star } from 'lucide-react';

interface Testimonial {
  id: string;
  quote: string;
  author: string;
  role: string;
  restaurant: string;
  city: string;
}

const TESTIMONIALS: Testimonial[] = [
  {
    id: 't-1',
    quote:
      'During a packed Saturday dinner rush, our broadband went completely dead. Traditional cloud POS software would have halted all billing. FoodPOS didn’t flinch — we punched 85+ orders and closed bills offline without losing a single rupee.',
    author: 'Amit Deshmukh',
    role: 'Managing Partner',
    restaurant: 'The Spice Pavilion',
    city: 'Pune',
  },
  {
    id: 't-2',
    quote:
      'The 90-second billing speed is real. Splitting tenders between Cash and UPI is seamless, and our end-of-shift drawer reconciliation variance dropped from ₹500 down to under ₹20 consistently.',
    author: 'Priya Raghavan',
    role: 'Operations Director',
    restaurant: 'Café Kaveri',
    city: 'Bengaluru',
  },
  {
    id: 't-3',
    quote:
      'Replacing paper KOT rolls with the Kitchen Display System (KDS) on a wall-mounted Android screen cut kitchen communication errors by 90%. Chefs love the clear prep timer and status progression.',
    author: 'Chef Kunal Malhotra',
    role: 'Head Chef & Co-founder',
    restaurant: 'Urban Handi',
    city: 'Delhi NCR',
  },
];

export const Testimonials: React.FC = () => {
  return (
    <section className="section" style={{ backgroundColor: 'var(--bg-porcelain)' }}>
      <div className="container">
        <div className="section-header">
          <span className="section-eyebrow">Proven on the Dining Floor</span>
          <h2 className="section-title">Trusted by Independent Restaurateurs Across India</h2>
          <p className="section-desc">
            See how FoodPOS keeps high-volume tables moving smoothly and registers balanced.
          </p>
        </div>

        <div className="testimonials-grid">
          {TESTIMONIALS.map((item) => (
            <div key={item.id} className="testimonial-card">
              <div style={{ display: 'flex', gap: '4px', marginBottom: '16px', color: 'var(--spice-ochre)' }}>
                {[...Array(5)].map((_, i) => (
                  <Star key={i} size={16} fill="currentColor" />
                ))}
              </div>

              <p className="testimonial-quote">&ldquo;{item.quote}&rdquo;</p>

              <div className="testimonial-author">
                <div className="author-avatar">
                  {item.author.split(' ').map((n) => n[0]).join('')}
                </div>
                <div className="author-info">
                  <h4>{item.author}</h4>
                  <p>
                    {item.role}, {item.restaurant} • {item.city}
                  </p>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
};
