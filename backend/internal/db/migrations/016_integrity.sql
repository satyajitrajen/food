-- 016: money / order integrity, refunds ledger, tender legs, order-item
-- snapshots, menu soft delete, outlet timezone, and indexes for the SQL
-- report aggregates. Money stays INTEGER paise.

-- ---- Orders: refunded status + cumulative refunds + payment metadata ----
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_status_check;
ALTER TABLE orders ADD CONSTRAINT orders_status_check
    CHECK (status IN ('received','preparing','ready','served','billing','completed','cancelled','refunded'));
ALTER TABLE orders ADD COLUMN IF NOT EXISTS refunded_paise INTEGER NOT NULL DEFAULT 0;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS payment_reference TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_id TEXT;
-- Default service charge as a percent of the discounted net (settings
-- service_percent copied at create time). 0 = flat service_paise only.
ALTER TABLE orders ADD COLUMN IF NOT EXISTS service_percent REAL NOT NULL DEFAULT 0;

-- Refund ledger (one row per refund; orders.refunded_paise is the rollup).
CREATE TABLE IF NOT EXISTS refunds (
    id           TEXT PRIMARY KEY,
    outlet_id    TEXT NOT NULL,
    order_id     TEXT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    amount_paise INTEGER NOT NULL CHECK (amount_paise > 0),
    mode         TEXT NOT NULL,
    reason       TEXT NOT NULL DEFAULT '',
    staff_id     TEXT,
    staff_name   TEXT,
    ts           TEXT NOT NULL,
    shift_id     TEXT
);
CREATE INDEX IF NOT EXISTS idx_refunds_order ON refunds(order_id);
CREATE INDEX IF NOT EXISTS idx_refunds_outlet_ts ON refunds(outlet_id, ts);

-- Tender legs booked at pay time (split payments → one row per leg). Old
-- orders have none; reports fall back to orders.payment_method.
CREATE TABLE IF NOT EXISTS order_payments (
    id           TEXT PRIMARY KEY,
    order_id     TEXT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    method       TEXT NOT NULL,
    amount_paise INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_order_payments_order ON order_payments(order_id);

-- ---- Order item snapshots (menu edits/deletes never rewrite history) ----
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS name TEXT;
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS variant_name TEXT;
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS is_veg INTEGER;
UPDATE order_items oi SET name = mi.name, is_veg = mi.is_veg
  FROM menu_items mi WHERE mi.id = oi.menu_item_id AND oi.name IS NULL;
UPDATE order_items oi SET variant_name = pv.name
  FROM product_variants pv WHERE pv.id = oi.variant_id AND oi.variant_name IS NULL;

-- ---- Menu soft delete (order_items keep their FK target) ----
ALTER TABLE menu_items ADD COLUMN IF NOT EXISTS is_deleted INTEGER NOT NULL DEFAULT 0;

-- ---- Expenses remember the shift whose drawer they hit ----
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS shift_id TEXT;

-- ---- Drawer count: loose coins total ----
ALTER TABLE shift_denominations ADD COLUMN IF NOT EXISTS coins_paise INTEGER NOT NULL DEFAULT 0;

-- ---- Outlet contact + timezone (report day boundaries) ----
ALTER TABLE outlets ADD COLUMN IF NOT EXISTS email TEXT NOT NULL DEFAULT '';
ALTER TABLE outlets ADD COLUMN IF NOT EXISTS timezone TEXT NOT NULL DEFAULT 'Asia/Kolkata';

-- ---- Settings: service_percent was displayed but never billed. It now
-- becomes the default service charge on dine-in orders, so the untouched
-- schema default (5.0) is reset to 0 to keep today's bills unchanged; owners
-- opt in by saving a value.
ALTER TABLE settings ALTER COLUMN service_percent SET DEFAULT 0;
UPDATE settings SET service_percent = 0 WHERE service_percent = 5.0;

-- ---- Razorpay one-off orders → org (manual renewal webhook fallback) ----
CREATE TABLE IF NOT EXISTS gateway_orders (
    order_id   TEXT PRIMARY KEY,
    org_id     TEXT NOT NULL,
    created_at TEXT NOT NULL
);

-- ---- Fixed-width UTC timestamps: normalize legacy RFC3339Nano text so
-- lexical range comparisons (paid_at BETWEEN …) stay correct.
UPDATE orders SET paid_at = to_char(paid_at::timestamptz AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  WHERE paid_at ~ '^\d{4}-\d{2}-\d{2}T';
UPDATE orders SET created_at = to_char(created_at::timestamptz AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  WHERE created_at ~ '^\d{4}-\d{2}-\d{2}T';
UPDATE expenses SET ts = to_char(ts::timestamptz AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  WHERE ts ~ '^\d{4}-\d{2}-\d{2}T';
UPDATE staff_attendance SET clock_in = to_char(clock_in::timestamptz AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  WHERE clock_in ~ '^\d{4}-\d{2}-\d{2}T';

-- ---- Indexes for scoped reads / report aggregates ----
CREATE INDEX IF NOT EXISTS idx_orders_outlet_paid ON orders(outlet_id, paid_at);
CREATE INDEX IF NOT EXISTS idx_orders_outlet_created ON orders(outlet_id, created_at);
CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_item_modifiers_item ON order_item_modifiers(order_item_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_item ON product_variants(menu_item_id);
CREATE INDEX IF NOT EXISTS idx_modifier_groups_item ON modifier_groups(menu_item_id);
CREATE INDEX IF NOT EXISTS idx_modifier_items_group ON modifier_items(group_id);
CREATE INDEX IF NOT EXISTS idx_menu_items_outlet ON menu_items(outlet_id);
CREATE INDEX IF NOT EXISTS idx_kots_outlet_created ON kots(outlet_id, created_at);
CREATE INDEX IF NOT EXISTS idx_expenses_outlet_ts ON expenses(outlet_id, ts);
