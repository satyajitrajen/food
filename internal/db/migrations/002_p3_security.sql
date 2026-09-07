-- 002: P3 (purchases/suppliers writes, stock log, customer credit) + P5 security (refresh tokens).

CREATE TABLE refresh_tokens (
    id TEXT PRIMARY KEY,
    staff_id TEXT NOT NULL REFERENCES staff(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    expires_at TEXT NOT NULL,
    revoked_at TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX idx_refresh_tokens_staff ON refresh_tokens(staff_id);

CREATE TABLE customer_credit_log (
    id TEXT PRIMARY KEY,
    outlet_id TEXT NOT NULL,
    customer_id TEXT NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK(kind IN ('sale','settlement')),
    amount_paise INTEGER NOT NULL CHECK(amount_paise > 0),
    reason TEXT NOT NULL,
    staff_id TEXT,
    staff_name TEXT,
    ts TEXT NOT NULL
);
CREATE INDEX idx_credit_log_customer ON customer_credit_log(customer_id, ts);

-- Offline-first clients pass their local ids so the server can echo them
-- back and the client can remap local→server ids after a replay.
ALTER TABLE orders ADD COLUMN client_id TEXT;
ALTER TABLE order_items ADD COLUMN client_id TEXT;
