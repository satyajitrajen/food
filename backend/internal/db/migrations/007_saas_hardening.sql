-- 007: SaaS hardening — GST on SaaS invoices, account tokens (verify/reset),
-- email verification flag.

ALTER TABLE saas_invoices ADD COLUMN gst_percent REAL NOT NULL DEFAULT 0;
ALTER TABLE saas_invoices ADD COLUMN tax_paise INTEGER NOT NULL DEFAULT 0;
ALTER TABLE saas_invoices ADD COLUMN gross_paise INTEGER NOT NULL DEFAULT 0;

ALTER TABLE accounts ADD COLUMN email_verified INTEGER NOT NULL DEFAULT 1;

-- Single-purpose, rotating account tokens (email verify / password reset).
CREATE TABLE account_tokens (
    id         TEXT PRIMARY KEY,
    account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    kind       TEXT NOT NULL CHECK (kind IN ('verify','reset')),
    token_hash TEXT NOT NULL UNIQUE,
    expires_at TEXT NOT NULL,
    used_at    TEXT,
    created_at TEXT NOT NULL
);
