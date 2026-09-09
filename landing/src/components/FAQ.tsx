import React, { useState } from 'react';
import { FAQS } from '../data/faqs';
import { ChevronDown } from 'lucide-react';

export const FAQ: React.FC = () => {
  const [openId, setOpenId] = useState<string | null>(FAQS[0].id);

  const toggleFaq = (id: string) => {
    setOpenId(openId === id ? null : id);
  };

  return (
    <section id="faq" className="section" style={{ backgroundColor: 'var(--bg-porcelain-warm)' }}>
      <div className="container">
        <div className="section-header">
          <span className="section-eyebrow">Clear Answers</span>
          <h2 className="section-title">Frequently Asked Questions</h2>
          <p className="section-desc">
            Everything you need to know about offline durability, hardware compatibility, and GST billing.
          </p>
        </div>

        <div className="faq-list">
          {FAQS.map((faq) => {
            const isOpen = openId === faq.id;
            return (
              <div key={faq.id} className={`faq-item ${isOpen ? 'open' : ''}`}>
                <button className="faq-question" onClick={() => toggleFaq(faq.id)}>
                  <span>{faq.question}</span>
                  <ChevronDown size={20} className="faq-icon" />
                </button>
                {isOpen && <div className="faq-answer">{faq.answer}</div>}
              </div>
            );
          })}
        </div>
      </div>
    </section>
  );
};
