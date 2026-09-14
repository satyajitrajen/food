-- 008: Bind kitchen staff to a single outlet (like waiters).
-- Kitchen terminals show one outlet's KDS; org-wide (outlet_id NULL) kitchen
-- rows would appear in every outlet roster and could operate any board.
-- Assign each unassigned kitchen row to its org's first outlet. Orgs without
-- an outlet keep the row unassigned: login then fails closed with
-- forbidden_outlet until an admin assigns one.
UPDATE staff SET outlet_id = (
  SELECT o.id FROM outlets o
  WHERE o.org_id = staff.org_id
  ORDER BY o.id ASC
  LIMIT 1
)
WHERE role = 'kitchen'
  AND (outlet_id IS NULL OR outlet_id = '')
  AND EXISTS (
    SELECT 1 FROM outlets o WHERE o.org_id = staff.org_id
  );
