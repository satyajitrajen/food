# FoodPOS React Landing Page & Google Play Policy Portal — Design Specification

**Date:** 2026-09-09  
**Status:** Approved  
**Target Directory:** `landing/`  

---

## 1. Executive Summary

FoodPOS is an offline-first restaurant Point-of-Sale (POS) system tailored for Indian food and beverage outlets (dine-in, cafés, QSRs, bars, and cloud kitchens).

This specification details the design for a modern, high-converting, component-driven **React + Vite** web landing page and Google Play compliance portal in `landing/`. It provides:
1. An immersive, interactive **Mini POS Terminal Simulator** with live GST math and offline-mode simulation.
2. A warm gourmet aesthetic (*Warm Gourmet Light Mode* with terracotta, warm saffron ochre, herbal emerald, and porcelain tones).
3. A multi-channel conversion funnel (*"Book a 15-Minute Demo"* modal + direct WhatsApp specialist chat).
4. Fully compliant **Google Play Store Policy Pages** (`/privacy-policy`, `/terms`, `/data-deletion`, `/refund-policy`) with direct URL routing required for Google Play Console review.

---

## 2. Target Audience & Core Value Propositions

* **Primary Persona:** Independent Indian restaurant, café, and QSR owners/operators looking to eliminate billing bottlenecks, double-billing errors, and internet outage chaos.
* **North-Star Metric Highlighted:** Complete shift opening, dine-in ordering, KOT dispatch, GST-compliant billing, and drawer reconciliation in under 90 seconds.
* **4 Core Pillars:**
  1. **Bulletproof Offline-First Engine:** Continues taking orders with zero connectivity; writes queue locally and syncs automatically without dropping payment events.
  2. **Lightning 90-Second Billing & Split Tender:** Cash, UPI, and Card splits with automated change calculation and CGST/SGST breakdown.
  3. **Kitchen Display System (KDS):** Live order ticket FSM (`new → preparing → ready → served`) with dedicated display-only role.
  4. **Shift & Cash Drawer Integrity:** Blind cash-count reconciliation targeting variance under ±₹50, full audit log of voids, refunds, and cash in/out.

---

## 3. Visual Identity & Design System

* **Base Surface:** Clean warm porcelain canvas (`#FAF7F2`) with crisp white elevated cards (`#FFFFFF`).
* **Accent Colors:**
  * **Terracotta Red / Clay (`#C84B31` / `#D95338`):** Primary brand CTA buttons, active state indicators.
  * **Warm Spice / Saffron Ochre (`#E28743` / `#D47700`):** Alert badges, KOT timers, warning highlights.
  * **Herbal Emerald (`#2D6A4F` / `#1B4332`):** Veg badges, payment settled pills, online sync indicator.
  * **Espresso Charcoal (`#1E1815` headings, `#5A4E47` body text):** High legibility typography.
* **Typography:** Plus Jakarta Sans / Outfit for punchy modern headlines; Inter for tabular billing numbers and monetary figures.
* **Styling Framework:** Vanilla CSS custom properties (`tokens.css`, `app.css`, `simulator.css`) to ensure maximum control, zero utility bloat, and sub-100ms load times.

---

## 4. Information Architecture & Components

```
landing/
├── index.html
├── package.json
├── tsconfig.json
├── vite.config.ts
└── src/
    ├── main.tsx
    ├── App.tsx
    ├── router.tsx                 # Client routing supporting /, /privacy-policy, /terms, /data-deletion, /refund-policy
    ├── data/
    │   ├── menuItems.ts           # Indian restaurant mock dishes (Biryani, Butter Chicken, Dosa, Coffee, etc.)
    │   └── faqs.ts                # FAQ questions & answers for restaurant owners
    ├── styles/
    │   ├── tokens.css             # Color palette, elevations, typography variables
    │   ├── app.css                # Global layout, hero, features, pricing, footer
    │   └── simulator.css          # POS terminal layout, receipt animation, cart panel
    ├── components/
    │   ├── Navbar.tsx             # Brand logo, nav links, Play Store badge, "Book Demo" button
    │   ├── Hero.tsx               # Headline, speed badge, dual CTAs, trust badges
    │   ├── PosSimulator.tsx       # Live interactive POS terminal with offline outage toggle
    │   ├── FeaturePillars.tsx     # 4 Core capability cards
    │   ├── FloorManagement.tsx    # Section & table status preview (AC Dining, Garden, Bar)
    │   ├── PlayStoreBanner.tsx    # Android tablet / Desktop app showcase & download banner
    │   ├── Pricing.tsx            # Starter (₹999), Pro (₹1,999), Enterprise (Custom) with Monthly/Annual switch
    │   ├── Testimonials.tsx       # Quotes from Indian restaurant owners (Mumbai, Pune, Bengaluru, Delhi)
    │   ├── FAQ.tsx                # Objections, GST compliance, thermal printer compatibility
    │   ├── DemoModal.tsx          # "Book a Demo" modal with instant confirmation & WhatsApp direct trigger
    │   └── Footer.tsx             # Sitemap, legal links, copyright
    └── pages/
        ├── HomePage.tsx           # Full landing experience
        ├── PrivacyPolicyPage.tsx  # Google Play compliant Privacy Policy
        ├── TermsPage.tsx          # Terms of Service
        ├── DataDeletionPage.tsx   # Google Play compliant Account & Data Deletion guidelines
        └── RefundPolicyPage.tsx   # Software subscription & refund policy
```

---

## 5. Google Play Store Required Legal Pages

1. **Privacy Policy (`/privacy-policy`)**:
   - Explicit disclosures on data collected (restaurant profile, staff names/PINs, customer contact numbers for bill dispatch, order transaction records).
   - Local device storage usage (SQLite/Hive cache for offline outbox persistence).
   - Device permissions: Internet/Network state, Camera (for barcode/QR scanning), Bluetooth/USB (for ESC/POS thermal printers).
   - Third-party data sharing (None for commercial monetization; solely transaction processing & cloud sync).
   - Data security standards (bcrypt PIN hashing, JWT authentication, HTTPS/TLS).

2. **Data Deletion & Account Erasure Instructions (`/data-deletion`)**:
   - Exact steps for restaurant owners or staff to request permanent data deletion.
   - Types of data deleted immediately (staff credentials, customer phone lists, menu catalogs).
   - Statutory retention requirements (GST invoicing audit logs retained as per Indian tax compliance).
   - Direct contact email and response turnaround time (< 48 hours).

3. **Terms of Service (`/terms`)** & **Refund Policy (`/refund-policy`)**:
   - SaaS licensing, multi-terminal use per outlet, subscription renewal, and cancellation terms.

---

## 6. Verification & Quality Gates

* **Build & Type Check:** `npm run build` with zero TypeScript or bundling errors.
* **Responsive Testing:** Fully adaptable across mobile, tablet (iPad / Android POS tablet), and desktop screens.
* **Interactive Simulator Validation:** Test adding items, changing quantity, verifying GST math (CGST 2.5% + SGST 2.5%), flipping offline toggle, and verifying receipt generation.
* **Play Store URLs:** Ensure `/privacy-policy`, `/terms`, and `/data-deletion` can be accessed and bookmarked directly.
