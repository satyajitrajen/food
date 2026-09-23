-- 014: purchase provenance on inventory items — batch number, storage rack
-- and purchase date (client sends these on inventory.create; server persists
-- and echoes them back so provenance survives across terminals).
ALTER TABLE inventory_items ADD COLUMN batch_no TEXT;
ALTER TABLE inventory_items ADD COLUMN rack_no TEXT;
ALTER TABLE inventory_items ADD COLUMN purchased_at TEXT;
