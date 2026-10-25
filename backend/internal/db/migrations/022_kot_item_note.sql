-- 022: carry the line's special instruction and add-on names on kitchen ticket
-- lines so the KDS shows them like the printed KOT does (both were dropped
-- when the ticket was built, so "extra spicy" never reached the kitchen screen).
ALTER TABLE kot_items ADD COLUMN note TEXT;
ALTER TABLE kot_items ADD COLUMN modifiers TEXT NOT NULL DEFAULT '';
