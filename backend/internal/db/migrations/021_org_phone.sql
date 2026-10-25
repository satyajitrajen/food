-- 021: optional owner contact number captured at sign-up, so the platform
-- can reach new restaurants (email was the only contact before).
ALTER TABLE organizations ADD COLUMN phone TEXT NOT NULL DEFAULT '';
