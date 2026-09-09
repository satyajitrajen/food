import React, { useState } from 'react';
import { MENU_ITEMS, MenuItem } from '../data/menuItems';
import {
  Wifi,
  WifiOff,
  Plus,
  Minus,
  Trash2,
  Printer,
  X,
  AlertCircle,
  ReceiptText,
} from 'lucide-react';

interface CartItem {
  item: MenuItem;
  quantity: number;
}

export const PosSimulator: React.FC = () => {
  const [selectedCategory, setSelectedCategory] = useState<string>('popular');
  const [isOffline, setIsOffline] = useState<boolean>(false);
  const [orderType, setOrderType] = useState<'dine-in' | 'takeaway' | 'delivery'>('dine-in');
  const [cart, setCart] = useState<CartItem[]>([
    { item: MENU_ITEMS[0], quantity: 1 }, // Hyderabadi Biryani
    { item: MENU_ITEMS[3], quantity: 2 }, // Filter Coffee
  ]);
  const [showReceipt, setShowReceipt] = useState<boolean>(false);
  const [receiptNotice, setReceiptNotice] = useState<string | null>(null);

  // Filter items by category
  const filteredItems =
    selectedCategory === 'popular'
      ? MENU_ITEMS
      : MENU_ITEMS.filter((i) => i.category === selectedCategory);

  // Cart operations
  const addToCart = (item: MenuItem) => {
    setCart((prev) => {
      const existing = prev.find((c) => c.item.id === item.id);
      if (existing) {
        return prev.map((c) =>
          c.item.id === item.id ? { ...c, quantity: c.quantity + 1 } : c
        );
      }
      return [...prev, { item, quantity: 1 }];
    });
  };

  const updateQuantity = (itemId: string, delta: number) => {
    setCart((prev) =>
      prev
        .map((c) => {
          if (c.item.id === itemId) {
            const newQty = c.quantity + delta;
            return newQty > 0 ? { ...c, quantity: newQty } : null;
          }
          return c;
        })
        .filter(Boolean) as CartItem[]
    );
  };

  const removeItem = (itemId: string) => {
    setCart((prev) => prev.filter((c) => c.item.id !== itemId));
  };

  const clearCart = () => {
    setCart([]);
    setShowReceipt(false);
  };

  // Billing calculation (matching FoodPOS integer paise engine)
  const subtotal = cart.reduce((sum, c) => sum + c.item.price * c.quantity, 0);
  const cgst = Math.round(subtotal * 0.025); // 2.5%
  const sgst = Math.round(subtotal * 0.025); // 2.5%
  const grandTotal = subtotal + cgst + sgst;

  const handleFireKOT = () => {
    if (cart.length === 0) return;
    setShowReceipt(true);
    if (isOffline) {
      setReceiptNotice('Order saved to local device storage. Queued for background cloud sync.');
    } else {
      setReceiptNotice('Order dispatched to Kitchen Display & synchronized to cloud database.');
    }
  };

  return (
    <div id="simulator" className="simulator-wrapper container">
      <div className={`simulator-terminal ${isOffline ? 'offline-mode' : ''}`}>
        {/* Terminal Header Bar */}
        <div className="terminal-header">
          <div className="terminal-header-left">
            <div className="terminal-dots">
              <div className="terminal-dot" style={{ backgroundColor: '#FF5F56' }} />
              <div className="terminal-dot" style={{ backgroundColor: '#FFBD2E' }} />
              <div className="terminal-dot" style={{ backgroundColor: '#27C93F' }} />
            </div>

            <div className="terminal-title-group">
              <span>FoodPOS Terminal #01</span>
              <span className="terminal-outlet-badge">Outlet: The Spice Pavilion</span>
              <span style={{ fontSize: '0.75rem', color: '#A89B92' }}>Staff: Rohan (Cashier)</span>
            </div>
          </div>

          <div className="terminal-header-right">
            {/* Interactive Wi-Fi Outage Toggle */}
            <div className="outage-toggle-wrap">
              <span>Simulate Internet:</span>
              <label className="toggle-switch">
                <input
                  type="checkbox"
                  checked={isOffline}
                  onChange={(e) => {
                    setIsOffline(e.target.checked);
                    setShowReceipt(false);
                  }}
                />
                <span className="toggle-slider" />
              </label>
              <span style={{ fontSize: '0.75rem', color: isOffline ? '#FFC085' : '#85E3B3' }}>
                {isOffline ? 'OFFLINE' : 'ONLINE'}
              </span>
            </div>

            {/* Live Indicator Pill */}
            <div className={`status-indicator-pill ${isOffline ? 'offline' : 'online'}`}>
              {isOffline ? (
                <>
                  <WifiOff size={14} />
                  <span>Offline Outbox Active</span>
                </>
              ) : (
                <>
                  <Wifi size={14} />
                  <span>Cloud Live Sync</span>
                </>
              )}
            </div>
          </div>
        </div>

        {/* Offline Simulated Notification Banner */}
        {isOffline && (
          <div className="simulator-alert-banner">
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <AlertCircle size={18} />
              <span>
                <strong>Simulated Outage Active:</strong> Broadband line is down. FoodPOS is writing orders directly to local device cache. Billing and KOT tickets remain 100% operational.
              </span>
            </div>
            <span style={{ fontSize: '0.75rem', opacity: 0.85 }}>0 Dropped Orders</span>
          </div>
        )}

        {/* Split Screen Terminal View */}
        <div className="terminal-body" style={{ position: 'relative' }}>
          {/* Left: Menu Catalog Pane */}
          <div className="catalog-pane">
            <div className="catalog-nav">
              {[
                { id: 'popular', label: '★ Popular' },
                { id: 'starters', label: 'Starters' },
                { id: 'mains', label: 'Mains & Curries' },
                { id: 'biryani', label: 'Biryani & Breads' },
                { id: 'beverages', label: 'Beverages' },
              ].map((cat) => (
                <button
                  key={cat.id}
                  className={`category-chip ${selectedCategory === cat.id ? 'active' : ''}`}
                  onClick={() => setSelectedCategory(cat.id)}
                >
                  {cat.label}
                </button>
              ))}
            </div>

            <div className="dish-grid">
              {filteredItems.map((item) => (
                <div key={item.id} className="dish-card">
                  <div>
                    {item.isVeg ? (
                      <div className="dish-veg-badge" title="Vegetarian">
                        <div className="dish-veg-dot" />
                      </div>
                    ) : (
                      <div className="dish-nonveg-badge" title="Non-Vegetarian">
                        <div className="dish-nonveg-dot" />
                      </div>
                    )}
                    <div className="dish-name">{item.name}</div>
                    <div className="dish-desc">{item.description}</div>
                  </div>

                  <div className="dish-footer">
                    <span className="dish-price">₹{item.price}</span>
                    <button onClick={() => addToCart(item)} className="dish-add-btn">
                      <Plus size={14} /> Add
                    </button>
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Right: Active Cart & Billing Pane */}
          <div className="cart-pane">
            <div className="cart-header">
              <div>
                <div style={{ fontWeight: 700, fontSize: '1rem', color: 'var(--text-espresso)' }}>
                  Active Order
                </div>
                <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>
                  Table T4 • Guest: Walk-in
                </div>
              </div>

              <div className="order-type-tabs">
                <button
                  className={`order-type-btn ${orderType === 'dine-in' ? 'active' : ''}`}
                  onClick={() => setOrderType('dine-in')}
                >
                  Dine-In
                </button>
                <button
                  className={`order-type-btn ${orderType === 'takeaway' ? 'active' : ''}`}
                  onClick={() => setOrderType('takeaway')}
                >
                  Takeaway
                </button>
              </div>
            </div>

            {/* Cart Items List */}
            {cart.length === 0 ? (
              <div className="cart-empty-state">
                <ReceiptText size={36} style={{ color: 'var(--border-active)', marginBottom: '8px' }} />
                <p>Your cart is empty.</p>
                <p style={{ fontSize: '0.8rem', color: 'var(--text-dim)' }}>
                  Click items on the left to add them to this table.
                </p>
              </div>
            ) : (
              <div className="cart-items-list">
                {cart.map(({ item, quantity }) => (
                  <div key={item.id} className="cart-item-row">
                    <div className="cart-item-info">
                      <span className="cart-item-title">{item.name}</span>
                      <span className="cart-item-unit-price">
                        ₹{item.price} &times; {quantity}
                      </span>
                    </div>

                    <div className="cart-item-controls">
                      <button onClick={() => updateQuantity(item.id, -1)} className="qty-btn">
                        <Minus size={12} />
                      </button>
                      <span className="qty-count">{quantity}</span>
                      <button onClick={() => updateQuantity(item.id, 1)} className="qty-btn">
                        <Plus size={12} />
                      </button>
                      <span className="cart-item-total">₹{item.price * quantity}</span>
                      <button
                        onClick={() => removeItem(item.id)}
                        className="qty-btn"
                        style={{ color: 'var(--non-veg-red)' }}
                        title="Remove"
                      >
                        <Trash2 size={12} />
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            )}

            {/* Bill Summary Breakdown */}
            <div className="bill-summary-box">
              <div className="bill-line-row">
                <span>Subtotal</span>
                <span>₹{subtotal}</span>
              </div>
              <div className="bill-line-row">
                <span>CGST (2.5%)</span>
                <span>₹{cgst}</span>
              </div>
              <div className="bill-line-row">
                <span>SGST (2.5%)</span>
                <span>₹{sgst}</span>
              </div>
              <div className="bill-line-row grand-total">
                <span>Grand Total</span>
                <span>₹{grandTotal}</span>
              </div>
            </div>

            {/* Actions */}
            <div className="terminal-action-group">
              <button
                onClick={handleFireKOT}
                disabled={cart.length === 0}
                className="btn btn-primary"
                style={{
                  width: '100%',
                  opacity: cart.length === 0 ? 0.5 : 1,
                  padding: '13px',
                }}
              >
                <Printer size={16} /> Fire KOT &amp; Print Bill
              </button>

              {cart.length > 0 && (
                <button
                  onClick={clearCart}
                  className="btn btn-secondary"
                  style={{ width: '100%', padding: '8px', fontSize: '0.8rem' }}
                >
                  Clear Order
                </button>
              )}
            </div>
          </div>

          {/* Animated Thermal Receipt Pop-out */}
          {showReceipt && cart.length > 0 && (
            <div className="thermal-receipt-modal">
              <button
                onClick={() => setShowReceipt(false)}
                style={{ position: 'absolute', top: '10px', right: '10px', color: '#7E7068' }}
              >
                <X size={16} />
              </button>

              <div className="receipt-header">
                <div className="receipt-brand">THE SPICE PAVILION</div>
                <div className="receipt-meta">FC Road, Shivajinagar, Pune</div>
                <div className="receipt-meta">GSTIN: 27AABCT1332L1Z5</div>
                <div style={{ margin: '6px 0', fontSize: '0.8rem', fontWeight: 700 }}>
                  TAX INVOICE #{Math.floor(1000 + Math.random() * 9000)}
                </div>
                <div className="receipt-meta">
                  Table: T4 • Waiter: Rohan • {new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                </div>
              </div>

              <table className="receipt-items-table">
                <tbody>
                  {cart.map(({ item, quantity }) => (
                    <tr key={item.id}>
                      <td>
                        {item.name} &times; {quantity}
                      </td>
                      <td style={{ textAlign: 'right', fontWeight: 600 }}>
                        ₹{item.price * quantity}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>

              <div style={{ fontSize: '0.75rem', display: 'flex', justifyContent: 'space-between', marginBottom: '4px' }}>
                <span>Subtotal:</span>
                <span>₹{subtotal}</span>
              </div>
              <div style={{ fontSize: '0.75rem', display: 'flex', justifyContent: 'space-between', marginBottom: '4px' }}>
                <span>CGST (2.5%):</span>
                <span>₹{cgst}</span>
              </div>
              <div style={{ fontSize: '0.75rem', display: 'flex', justifyContent: 'space-between', marginBottom: '6px' }}>
                <span>SGST (2.5%):</span>
                <span>₹{sgst}</span>
              </div>

              <div style={{ display: 'flex', justifyContent: 'space-between', fontWeight: 800, fontSize: '0.95rem', borderTop: '1px solid #A89B92', paddingTop: '6px' }}>
                <span>TOTAL:</span>
                <span>₹{grandTotal}</span>
              </div>

              <div className="receipt-gst-badge">
                ✓ 5% GST COMPLIANT INVOICE
              </div>

              {isOffline ? (
                <div className="receipt-offline-stamp">
                  ⚡ OFFLINE QUEUE: SAVED TO DEVICE DISK
                </div>
              ) : (
                <div style={{ marginTop: '10px', fontSize: '0.7rem', textAlign: 'center', color: '#2D6A4F' }}>
                  ✓ SYNCED TO CLOUD LEDGER
                </div>
              )}

              {receiptNotice && (
                <div style={{ marginTop: '8px', fontSize: '0.68rem', textAlign: 'center', color: '#7E7068', fontStyle: 'italic' }}>
                  {receiptNotice}
                </div>
              )}

              <div style={{ marginTop: '14px', textAlign: 'center', fontSize: '0.7rem', color: '#7E7068' }}>
                Thank you for dining with us!
              </div>

              <div className="receipt-cut-edge" />
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
