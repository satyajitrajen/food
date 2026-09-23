-- 012: Shorten the free trial from 14 days to 7 days.
-- New organizations get trial_ends_at = now + plan.trial_days (7) at
-- registration. Existing in-flight trials keep their trial_ends_at; only the
-- plan catalog default is updated so the next seed/upsert converges to 7.

ALTER TABLE plans ALTER COLUMN trial_days SET DEFAULT 7;
UPDATE plans SET trial_days = 7 WHERE trial_days = 14;
