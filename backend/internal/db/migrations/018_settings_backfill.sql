-- Outlets created through self-signup never got a settings row, so their
-- bills fell back to hard-coded charges. Give every outlet one.
INSERT INTO settings (outlet_id, restaurant_name, service_percent)
SELECT o.id, o.name, 0 FROM outlets o
WHERE NOT EXISTS (SELECT 1 FROM settings s WHERE s.outlet_id = o.id);
