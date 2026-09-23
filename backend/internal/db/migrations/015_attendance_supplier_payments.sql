-- 015: staff attendance ledger + supplier payment ledger.
-- Attendance: auto clock-in on staff login, auto clock-out on logout;
-- server truth replaces the terminal-local ledger on hydration.
-- Supplier payments: direct payouts against a supplier's outstanding due
-- (previously only derivable from pending-purchase settlement).
CREATE TABLE IF NOT EXISTS staff_attendance (
    id         TEXT PRIMARY KEY,
    org_id     TEXT NOT NULL,
    outlet_id  TEXT NOT NULL,
    staff_id   TEXT NOT NULL,
    staff_name TEXT NOT NULL,
    clock_in   TEXT NOT NULL,
    clock_out  TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_staff_attendance_staff ON staff_attendance(staff_id, clock_in);
CREATE INDEX IF NOT EXISTS idx_staff_attendance_org ON staff_attendance(org_id, clock_in);

CREATE TABLE IF NOT EXISTS supplier_payments (
    id           TEXT PRIMARY KEY,
    outlet_id    TEXT NOT NULL,
    supplier_id  TEXT NOT NULL,
    supplier_name TEXT NOT NULL,
    amount       INTEGER NOT NULL CHECK (amount > 0),
    method       TEXT NOT NULL DEFAULT 'cash',
    reference    TEXT,
    staff_id     TEXT,
    staff_name   TEXT,
    ts           TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_supplier_payments_outlet ON supplier_payments(outlet_id, supplier_id, ts);
