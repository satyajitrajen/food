-- 010: Razorpay Subscriptions (auto-renew). Plans link to their gateway plan;
-- org subscriptions track the hosted subscription id and the gateway-side
-- status. Gateway lifecycle events (subscription.*) keep these in sync.

ALTER TABLE plans ADD COLUMN gateway_plan_id TEXT NOT NULL DEFAULT '';
ALTER TABLE org_subscriptions ADD COLUMN gateway_subscription_id TEXT NOT NULL DEFAULT '';
ALTER TABLE org_subscriptions ADD COLUMN gateway_status TEXT NOT NULL DEFAULT '';
CREATE INDEX IF NOT EXISTS idx_org_subscriptions_gateway ON org_subscriptions(gateway_subscription_id);

-- Webhook idempotency: one invoice per gateway payment reference per org
-- (backing constraint for the subscription.charged duplicate guard). NULL
-- references (manual entries without one) stay unrestricted.
CREATE UNIQUE INDEX IF NOT EXISTS idx_saas_invoices_org_reference
    ON saas_invoices(org_id, reference) WHERE reference IS NOT NULL AND reference != '';
