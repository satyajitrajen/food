-- 006: SaaS — organizations, owner accounts, platform admins, plans &
-- subscriptions. Adds an org layer above outlets and scopes staff to org/outlet.
-- Money stays INTEGER paise (D-001). Timestamps are RFC3339 TEXT like the rest.

-- ---- Organizations (the tenant) ----
CREATE TABLE IF NOT EXISTS organizations (
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    email      TEXT NOT NULL,
    gstin      TEXT NOT NULL DEFAULT '',
    status     TEXT NOT NULL DEFAULT 'trial'
               CHECK (status IN ('trial','active','past_due','suspended','expired','closed')),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- Owner accounts (email + password). "owner" is the primary account holder.
CREATE TABLE IF NOT EXISTS accounts (
    id            TEXT PRIMARY KEY,
    org_id        TEXT NOT NULL REFERENCES organizations(id),
    name          TEXT NOT NULL,
    email         TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role          TEXT NOT NULL DEFAULT 'owner' CHECK (role IN ('owner','admin')),
    is_active     INTEGER NOT NULL DEFAULT 1,
    created_at    TEXT NOT NULL
);

-- Platform (super) admins — separate from tenant staff/owners.
CREATE TABLE IF NOT EXISTS platform_admins (
    id            TEXT PRIMARY KEY,
    name          TEXT NOT NULL,
    email         TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    created_at    TEXT NOT NULL
);

-- Short join codes so POS terminals can discover an org's outlets/staff pre-login.
CREATE TABLE IF NOT EXISTS org_codes (
    org_id     TEXT NOT NULL REFERENCES organizations(id),
    code       TEXT NOT NULL UNIQUE,
    active     INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL
);

-- Billing plans (single "pro" plan seeded by the server; superadmin can add more).
CREATE TABLE IF NOT EXISTS plans (
    id            TEXT PRIMARY KEY,
    code          TEXT NOT NULL UNIQUE,
    name          TEXT NOT NULL,
    price_paise   INTEGER NOT NULL,
    interval_days INTEGER NOT NULL DEFAULT 30,
    max_outlets   INTEGER NOT NULL DEFAULT 1,
    max_staff     INTEGER NOT NULL DEFAULT 20,
    trial_days    INTEGER NOT NULL DEFAULT 14,
    is_active     INTEGER NOT NULL DEFAULT 1
);

-- One subscription per org.
CREATE TABLE IF NOT EXISTS org_subscriptions (
    org_id               TEXT PRIMARY KEY REFERENCES organizations(id),
    plan_id              TEXT NOT NULL REFERENCES plans(id),
    status               TEXT NOT NULL
                         CHECK (status IN ('trial','active','past_due','suspended','expired','cancelled')),
    trial_ends_at        TEXT,
    current_period_start TEXT,
    current_period_end   TEXT,
    cancel_at_period_end INTEGER NOT NULL DEFAULT 0,
    notes                TEXT,
    updated_at           TEXT NOT NULL
);

-- SaaS invoices (manual billing records; Razorpay later records here too).
CREATE TABLE IF NOT EXISTS saas_invoices (
    id           TEXT PRIMARY KEY,
    org_id       TEXT NOT NULL REFERENCES organizations(id),
    invoice_no   TEXT NOT NULL,
    amount_paise INTEGER NOT NULL,
    method       TEXT NOT NULL DEFAULT 'bank',
    period_start TEXT,
    period_end   TEXT,
    paid_at      TEXT NOT NULL,
    reference    TEXT,
    notes        TEXT,
    created_by   TEXT,
    created_at   TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_saas_invoices_org ON saas_invoices(org_id, created_at);

-- Subscription lifecycle audit trail.
CREATE TABLE IF NOT EXISTS org_events (
    id      TEXT PRIMARY KEY,
    org_id  TEXT NOT NULL REFERENCES organizations(id),
    actor   TEXT,
    action  TEXT NOT NULL,
    meta    TEXT NOT NULL DEFAULT '{}',
    ts      TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_org_events_org ON org_events(org_id, ts);

-- Generic rotating sessions for owner + platform-admin logins (staff keep the
-- legacy refresh_tokens table).
CREATE TABLE IF NOT EXISTS auth_refresh (
    id         TEXT PRIMARY KEY,
    scope      TEXT NOT NULL CHECK (scope IN ('staff','owner','admin')),
    actor_id   TEXT NOT NULL,
    token_hash TEXT NOT NULL UNIQUE,
    expires_at TEXT NOT NULL,
    revoked_at TEXT,
    created_at TEXT NOT NULL
);
-- Session tenant binding for staff sessions (owner/admin have no outlet).
ALTER TABLE auth_refresh ADD COLUMN org_id TEXT;
ALTER TABLE auth_refresh ADD COLUMN outlet_id TEXT;

-- ---- Tenant columns on existing tables ----
ALTER TABLE outlets ADD COLUMN org_id TEXT NOT NULL DEFAULT 'org-01';
ALTER TABLE staff   ADD COLUMN org_id TEXT NOT NULL DEFAULT 'org-01';
ALTER TABLE staff   ADD COLUMN outlet_id TEXT;
ALTER TABLE audit_log ADD COLUMN org_id TEXT;
ALTER TABLE audit_log ADD COLUMN outlet_id TEXT;

-- ---- SaaS invoice counter kind ----
ALTER TABLE counters DROP CONSTRAINT IF EXISTS counters_kind_check;
ALTER TABLE counters ADD CONSTRAINT counters_kind_check
    CHECK (kind IN ('order','kot','invoice','saas_invoice'));

-- ---- Demo organization for existing (pre-SaaS) data ----
INSERT INTO organizations (id, name, email, gstin, status, created_at, updated_at)
VALUES ('org-01', 'Spice Haven', 'demo@spicehaven.test', '27AAAAA0000A1Z5', 'active',
        to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
ON CONFLICT (id) DO NOTHING;

-- Existing outlets/staff belong to the demo org; staff keep org-wide access
-- (outlet_id NULL) so legacy terminals can still reach every outlet they could.
INSERT INTO org_codes (org_id, code, active, created_at)
VALUES ('org-01', 'SPICE-HAVEN', 1,
        to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
ON CONFLICT (code) DO NOTHING;

-- Subscriptions/plan are seeded by the server (needs bcrypt-free static rows +
-- runtime timestamps); see cmd/server/main.go seedPlanAndOrg.
