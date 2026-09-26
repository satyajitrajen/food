# Version Changelog & Release Tracking

All notable changes and releases for the **Hishobkr FoodPOS** Android application are documented in this file.

The project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html) (`MAJOR.MINOR.PATCH+BUILD`).

---

## [1.0.1] - 2026-09-26 (Current Version)
- **Version Name:** `1.0.1`
- **Version Code (Build Number):** `2`
- **Artifact:** `build/app/outputs/bundle/release/app-release.aab`
- **Play Store Status:** Ready for Upload / Staged

### 🌟 New Features & Improvements
- **Menu & Catalog Enhancements:**
  - Automatic catalog synchronization and instant menu refresh whenever the menu screen opens.
  - Ability to create and manage custom menu categories on the fly.
  - Strict tenant and outlet isolation for menus, items, and pricing.
- **Table & Floor Management:**
  - **Quick Table Reset:** Long-press any table to immediately reset its status back to "Available" (clearing stuck/ghost table locks).
  - **Floor Status Filters:** Added visual filters to sort floor tables by status (Available, Occupied, Billed, KOT Active).
- **Kitchen & KOT Workflow:**
  - Vegetarian (`Veg`) / Non-Vegetarian flags on printed KOTs and the live Kitchen Display System (KDS).
  - Multi-outlet staff constraints: bound kitchen display and kitchen staff strictly to their assigned outlet.
- **Staff Attribution & Usability:**
  - Waiter-scoped running orders: Waiters see and manage their own tables and assigned orders.
  - Persistent staff login session: Sessions remain active until staff explicitly logs out.
  - Searchable staff profile & PIN selector for quicker terminal switching.
- **Financials, Expenses & Reports:**
  - Extended business reports with server-side custom date range filtering.
  - Added cash ledger tracking and supplier payment disbursement management.
  - Staff attendance tracking integration.
- **Data Integrity & Architecture:**
  - Server-first boot configuration: connected terminals boot directly against live server state with zero fabricated/demo records.
  - Clean static analysis across all Dart/Flutter modules.

---

## [1.0.0] - Initial Release
- **Version Name:** `1.0.0`
- **Version Code (Build Number):** `1`
- **Artifact:** `build/app/outputs/bundle/release/app-release.aab`
- **Play Store Status:** Published / Live on Google Play Store

### 🚀 Initial Launch Features
- **Offline-First Restaurant POS:**
  - Complete offline order capture with background outbox synchronization over REST + SSE.
  - Support for multiple order types: Dine-In, Takeaway, and Quick Delivery.
- **Order & Bill Management:**
  - Real-time cart calculations, taxes (GST), discounts, and service charges.
  - Split billing, table-to-bill conversion, and payment method handling (Cash, UPI, Card).
  - 58mm/80mm thermal receipt printing and digital bill generation.
- **Kitchen Display System (KDS) & KOTs:**
  - Real-time KOT generation per table or takeaway order.
  - Interactive kitchen board showing pending, preparing, and completed tickets.
- **Shift & Cash Management:**
  - Cash float initialization, mid-shift payouts/pay-ins, and end-of-shift reconciliation reports.
- **Multi-Role Access Control:**
  - Role-based permissions supporting Admin, Owner, Manager, Cashier, Waiter, and Kitchen staff.
  - Quick 4-digit PIN authentication.
- **SaaS Tenancy & Branding:**
  - Multi-organization onboarding, tenant code routing, and subscription plan management.
  - Integration with Razorpay for subscription renewals.
  - Rebranded identity with official Hishobkr logo, dark green theme, and responsive UI.
