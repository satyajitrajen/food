-- 011: device_tokens for Firebase Cloud Messaging (FCM) push notifications.
CREATE TABLE IF NOT EXISTS device_tokens (
    token TEXT PRIMARY KEY,
    org_id TEXT NOT NULL,
    outlet_id TEXT NOT NULL,
    staff_id TEXT NOT NULL DEFAULT '',
    platform TEXT NOT NULL DEFAULT 'android',
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_device_tokens_outlet ON device_tokens (outlet_id);
CREATE INDEX IF NOT EXISTS idx_device_tokens_org ON device_tokens (org_id);
