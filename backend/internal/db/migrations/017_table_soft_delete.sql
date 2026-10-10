-- 017: tables can be removed without breaking order history (orders keep
-- their table_id), and a removed table's number can be reused.
ALTER TABLE tables ADD COLUMN IF NOT EXISTS is_deleted INTEGER NOT NULL DEFAULT 0;
ALTER TABLE tables DROP CONSTRAINT IF EXISTS tables_outlet_id_table_number_key;
CREATE UNIQUE INDEX IF NOT EXISTS uq_tables_outlet_number_live
    ON tables (outlet_id, table_number) WHERE is_deleted = 0;
