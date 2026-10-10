-- 019: customers, suppliers and inventory items can be removed without
-- breaking history (credit log, purchases, stock log keep their rows).
ALTER TABLE customers ADD COLUMN IF NOT EXISTS is_deleted INTEGER NOT NULL DEFAULT 0;
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS is_deleted INTEGER NOT NULL DEFAULT 0;
ALTER TABLE inventory_items ADD COLUMN IF NOT EXISTS is_deleted INTEGER NOT NULL DEFAULT 0;
