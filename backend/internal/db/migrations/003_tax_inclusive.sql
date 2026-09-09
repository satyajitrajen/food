-- B1 (FR-O3): inclusive-GST pricing. The order remembers whether its menu
-- prices already contain GST; billing math extracts the tax instead of adding it.
ALTER TABLE orders ADD COLUMN is_tax_inclusive INTEGER NOT NULL DEFAULT 0;
