import React, { useState } from 'react';
import { Users, ArrowRightLeft, Merge } from 'lucide-react';

interface TablePreview {
  id: string;
  name: string;
  seats: number;
  status: 'available' | 'occupied' | 'billing';
  orderSummary?: string;
}

const SECTION_TABLES: Record<string, TablePreview[]> = {
  'AC Dining': [
    { id: 't1', name: 'Table A1', seats: 4, status: 'occupied', orderSummary: '3 Items • ₹680' },
    { id: 't2', name: 'Table A2', seats: 2, status: 'available' },
    { id: 't3', name: 'Table A3', seats: 6, status: 'billing', orderSummary: 'Bill Printed • ₹1,420' },
    { id: 't4', name: 'Table A4', seats: 4, status: 'available' },
    { id: 't5', name: 'Table A5', seats: 8, status: 'occupied', orderSummary: '5 Items • ₹2,150' },
  ],
  'Garden Lounge': [
    { id: 'g1', name: 'Garden G1', seats: 4, status: 'occupied', orderSummary: '2 Items • ₹480' },
    { id: 'g2', name: 'Garden G2', seats: 6, status: 'available' },
    { id: 'g3', name: 'Garden G3', seats: 4, status: 'available' },
    { id: 'g4', name: 'Garden Gazebo', seats: 10, status: 'billing', orderSummary: 'Bill Printed • ₹3,890' },
  ],
  'Bar Counter': [
    { id: 'b1', name: 'Bar Stool B1', seats: 1, status: 'occupied', orderSummary: '1 Item • ₹350' },
    { id: 'b2', name: 'Bar Stool B2', seats: 1, status: 'available' },
    { id: 'b3', name: 'Bar Stool B3', seats: 1, status: 'available' },
    { id: 'b4', name: 'High Table B4', seats: 4, status: 'occupied', orderSummary: '4 Items • ₹1,820' },
  ],
};

export const FloorManagement: React.FC = () => {
  const [activeSection, setActiveSection] = useState<string>('AC Dining');
  const tables = SECTION_TABLES[activeSection] || [];

  return (
    <section id="floors" className="section" style={{ backgroundColor: 'var(--bg-porcelain-warm)' }}>
      <div className="container">
        <div className="section-header">
          <span className="section-eyebrow">Table & Floor Architecture</span>
          <h2 className="section-title">Visual Dining Sections & Fast Table Operations</h2>
          <p className="section-desc">
            Manage multi-zone layouts effortlessly. Move active orders between tables, merge tables for large banquet parties, and track real-time occupancy.
          </p>
        </div>

        <div className="floor-preview-box">
          {/* Section Tabs */}
          <div className="floor-tabs">
            {Object.keys(SECTION_TABLES).map((section) => (
              <button
                key={section}
                className={`floor-tab ${activeSection === section ? 'active' : ''}`}
                onClick={() => setActiveSection(section)}
              >
                {section}
              </button>
            ))}
          </div>

          {/* Tables Grid */}
          <div className="tables-grid">
            {tables.map((table) => (
              <div key={table.id} className="table-card">
                <div className="table-name">{table.name}</div>
                <div className="table-capacity">
                  <Users size={12} style={{ display: 'inline', verticalAlign: 'middle', marginRight: '4px' }} />
                  {table.seats} Seats
                </div>

                <div style={{ marginBottom: '8px' }}>
                  <span className={`table-status-pill status-${table.status}`}>
                    {table.status.toUpperCase()}
                  </span>
                </div>

                {table.orderSummary && (
                  <div style={{ fontSize: '0.75rem', fontWeight: 600, color: 'var(--text-body)' }}>
                    {table.orderSummary}
                  </div>
                )}
              </div>
            ))}
          </div>

          {/* Table Operations Footer Bar */}
          <div style={{ marginTop: '28px', paddingTop: '20px', borderTop: '1px solid var(--border-soft)', display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: '16px' }}>
            <div style={{ display: 'flex', gap: '20px', fontSize: '0.85rem', color: 'var(--text-muted)' }}>
              <span><strong style={{ color: 'var(--emerald-herbal)' }}>Green:</strong> Ready for Seating</span>
              <span><strong style={{ color: 'var(--terracotta)' }}>Red:</strong> Active Dining Order</span>
              <span><strong style={{ color: 'var(--spice-ochre-dark)' }}>Amber:</strong> Check Presented / Billing</span>
            </div>

            <div style={{ display: 'flex', gap: '12px' }}>
              <span className="feature-metric-badge">
                <ArrowRightLeft size={14} /> Move Table (Auto-rehomes order)
              </span>
              <span className="feature-metric-badge">
                <Merge size={14} /> Merge & Unmerge Tables
              </span>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};
