-- 004: PostgreSQL compatibility. SQLite's implicit rowid (used for stable
-- insertion-order reads) is replaced with explicit sequence columns.
CREATE SEQUENCE IF NOT EXISTS seq_order_items;
ALTER TABLE order_items ADD COLUMN seq BIGINT NOT NULL DEFAULT nextval('seq_order_items');

CREATE SEQUENCE IF NOT EXISTS seq_order_item_modifiers;
ALTER TABLE order_item_modifiers ADD COLUMN seq BIGINT NOT NULL DEFAULT nextval('seq_order_item_modifiers');

CREATE SEQUENCE IF NOT EXISTS seq_product_variants;
ALTER TABLE product_variants ADD COLUMN seq BIGINT NOT NULL DEFAULT nextval('seq_product_variants');
