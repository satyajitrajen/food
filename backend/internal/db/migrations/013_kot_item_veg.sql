-- 013: carry the veg/non-veg flag on kitchen ticket lines so the KDS renders
-- the correct FSSAI mark (previously every line defaulted to veg on the app).
ALTER TABLE kot_items ADD COLUMN is_veg INTEGER NOT NULL DEFAULT 1;
