// Single advertised plan. Must stay in sync with the backend catalog seeded
// in backend/internal/store/saas.go (defaultPlans): code "pro", 199900 paise,
// 365 days, max 5 outlets, max 20 staff, 7-day trial.
export const PLAN = {
  code: 'pro',
  name: 'Pro Dining (Annual)',
  shortName: 'Pro Dining',
  priceLabel: '₹1,999',
  period: 'year',
  maxOutlets: 5,
  maxStaff: 20,
  trialDays: 7,
} as const;

export const REGISTER_PATH = `/console/register?plan=${PLAN.code}`;
