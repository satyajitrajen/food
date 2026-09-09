-- 005: Kitchen display role + managed dining sections.
--
-- Kitchen is a display-only role: it logs in on the KOT board terminal and
-- never touches money. The route layer (DenyRoles) enforces what it may call;
-- this migration only lets the role exist.
ALTER TABLE staff DROP CONSTRAINT IF EXISTS staff_role_check;
ALTER TABLE staff ADD CONSTRAINT staff_role_check
    CHECK (role IN ('admin','manager','cashier','waiter','kitchen'));

-- Settings gains an ordered, JSON-encoded list of dining sections
-- (e.g. ["Garden","AC Dining","Bar"]). Tables keep their free-text floor,
-- which IS the section name. An empty list means "derive from table floors".
ALTER TABLE settings ADD COLUMN sections TEXT NOT NULL DEFAULT '[]';
