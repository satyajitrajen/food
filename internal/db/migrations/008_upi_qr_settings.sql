-- 008: UPI QR payment settings (per outlet).
-- upi_id (e.g. name@okhdfcbank) is the primary source; the POS generates a
-- per-bill QR from it. upi_qr_image is an optional uploaded override for
-- bank-branded QR images (/media/... path).
ALTER TABLE settings ADD COLUMN upi_id TEXT NOT NULL DEFAULT '';
ALTER TABLE settings ADD COLUMN upi_name TEXT NOT NULL DEFAULT '';
ALTER TABLE settings ADD COLUMN upi_qr_image TEXT NOT NULL DEFAULT '';
