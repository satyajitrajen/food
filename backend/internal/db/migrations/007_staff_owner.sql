-- 007: Protect the main (owner) admin.
-- The RegisterOrg admin (role='admin', outlet_id NULL) is the owner shadow and
-- must never be deactivated/demoted by any POS staff token, nor edited by
-- anyone except itself. Later admins are regular rows (is_protected=0).
ALTER TABLE staff ADD COLUMN IF NOT EXISTS is_protected INTEGER NOT NULL DEFAULT 0;

-- Backfill: oldest admin with outlet_id NULL per org becomes the protected
-- owner. ctid gives insertion order on PostgreSQL (NewID is random, so id
-- ordering is meaningless). Orgs with no such row get none (logged by seed).
UPDATE staff s SET is_protected = 1 WHERE s.id IN (
  SELECT DISTINCT ON (org_id) id FROM staff
  WHERE role = 'admin' AND outlet_id IS NULL AND org_id IS NOT NULL
  ORDER BY org_id, ctid ASC
) AND COALESCE(s.is_protected, 0) = 0;
