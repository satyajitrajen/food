-- 009: marketing leads captured by the landing demo/pricing forms. Public
-- write endpoint; the superadmin console lists them for follow-up.

CREATE TABLE IF NOT EXISTS leads (
    id              TEXT PRIMARY KEY,
    restaurant_name TEXT NOT NULL,
    contact_name    TEXT NOT NULL DEFAULT '',
    phone           TEXT NOT NULL,
    city            TEXT NOT NULL DEFAULT '',
    outlet_format   TEXT NOT NULL DEFAULT '',
    plan_interest   TEXT NOT NULL DEFAULT '',
    source          TEXT NOT NULL DEFAULT 'landing',
    status          TEXT NOT NULL DEFAULT 'new',
    created_at      TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_leads_created ON leads(created_at DESC);
