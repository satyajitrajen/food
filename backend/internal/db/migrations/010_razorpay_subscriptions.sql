-- 010: Razorpay Subscriptions (auto-renew). Plans link to their gateway plan;
-- org subscriptions track the hosted subscription id and the gateway-side
-- status. Gateway lifecycle events (subscription.*) keep these in sync.

ALTER TABLE plans ADD COLUMN gateway_plan_id TEXT NOT NULL DEFAULT '';
ALTER TABLE org_subscriptions ADD COLUMN gateway_subscription_id TEXT NOT NULL DEFAULT '';
ALTER TABLE org_subscriptions ADD COLUMN gateway_status TEXT NOT NULL DEFAULT '';
CREATE INDEX IF NOT EXISTS idx_org_subscriptions_gateway ON org_subscriptions(gateway_subscription_id);
