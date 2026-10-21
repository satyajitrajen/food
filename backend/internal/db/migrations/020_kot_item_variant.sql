-- 020: carry the portion/variant name on kitchen ticket lines so the KDS and
-- the printed KOT show Half/Full (the variant was previously dropped when the
-- ticket was built, so the kitchen could not tell portions apart).
ALTER TABLE kot_items ADD COLUMN variant_name TEXT;
