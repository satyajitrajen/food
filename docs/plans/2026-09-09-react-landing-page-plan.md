# FoodPOS React Landing Page & Google Play Portal Implementation Plan

> **For Cursor / Antigravity:** Use executing-plans skill or subagent-driven development to implement this plan task-by-task.

**Goal:** Build a high-converting, component-driven React (Vite + TypeScript) landing page and Google Play compliance portal in `landing/` featuring an interactive Mini POS Terminal Simulator, Warm Gourmet Light Mode aesthetic, demo booking modal with WhatsApp integration, and mandatory Google Play policy pages.

**Architecture:** A standalone Vite + React + TypeScript SPA in `landing/` using a bespoke Vanilla CSS design token system (`tokens.css`, `app.css`, `simulator.css`) and client-side path/history routing to serve the home landing experience and direct-accessible legal pages (`/privacy-policy`, `/terms`, `/data-deletion`, `/refund-policy`).

**Tech Stack:** React 18, TypeScript, Vite, Lucide React icons, Google Fonts (Plus Jakarta Sans & Inter), Vanilla CSS.

---

### Task 1: Scaffold Vite + React + TypeScript in `landing/`
- **Files:** `landing/package.json`, `landing/tsconfig.json`, `landing/vite.config.ts`, `landing/index.html`
- **Actions:**
  1. Initialize Vite React TypeScript project in `landing/`.
  2. Install `lucide-react` for icons.
  3. Configure Google Fonts (*Plus Jakarta Sans* and *Inter*) and page metadata in `landing/index.html`.
- **Verification:** Run `npm run build` in `landing/` to verify clean scaffolding.

---

### Task 2: Implement Design Tokens & Global Stylesheet
- **Files:**
  - `landing/src/styles/tokens.css`
  - `landing/src/styles/app.css`
  - `landing/src/styles/simulator.css`
- **Actions:**
  1. Define CSS custom properties:
     - Surface: `--bg-porcelain: #FAF7F2`, `--surface-white: #FFFFFF`, `--border-soft: #EDE6DD`
     - Brand: `--terracotta: #C84B31`, `--terracotta-hover: #B03E26`
     - Accents: `--spice-ochre: #E28743`, `--emerald-veg: #2D6A4F`, `--espresso: #1E1815`
  2. Implement responsive grid layouts, card elevations, badge pills, and typography classes.
  3. Implement POS terminal simulator specific styles: split screen, dish cards, cart panel, receipt animation, and offline state banners.
- **Verification:** Verify CSS imports in `main.tsx`.

---

### Task 3: Build Mock Data (Menu Catalog & Objections FAQ)
- **Files:**
  - `landing/src/data/menuItems.ts`
  - `landing/src/data/faqs.ts`
- **Actions:**
  1. Create structured catalog of Indian dishes with categories (*Starters*, *Mains*, *Biryani*, *Breads*, *Beverages*), Veg/Non-Veg flags, descriptions, and prices in ₹.
  2. Create FAQ questions and answers addressing offline tolerance, GST calculation, ESC/POS thermal printing, and Android hardware requirements.
- **Verification:** Import data and verify TypeScript interfaces compile cleanly.

---

### Task 4: Implement Client Router & Play Store Required Legal Pages
- **Files:**
  - `landing/src/router.tsx`
  - `landing/src/pages/PrivacyPolicyPage.tsx`
  - `landing/src/pages/TermsPage.tsx`
  - `landing/src/pages/DataDeletionPage.tsx`
  - `landing/src/pages/RefundPolicyPage.tsx`
- **Actions:**
  1. Build a client-side route switcher that reacts to URL paths (`/`, `/privacy-policy`, `/terms`, `/data-deletion`, `/refund-policy`) and supports direct browser back/forward navigation.
  2. Write comprehensive, legally sound Google Play policies:
     - **Privacy Policy**: Explicit disclosure of restaurant credentials, staff PINs, customer phone numbers for digital receipt dispatch, local device storage (SQLite offline cache), network/camera/bluetooth printer permissions.
     - **Data Deletion**: Clear instructions for account removal, contact email, and data retention rules under statutory GST audits.
     - **Terms of Service & Refund Policy**: SaaS licensing, multi-terminal permissions, subscription terms.
- **Verification:** Verify navigation between routes and rendering of legal documents.

---

### Task 5: Build Core Landing Components (Navbar, Hero, Feature Pillars, Pricing, Testimonials, Footer)
- **Files:**
  - `landing/src/components/Navbar.tsx`
  - `landing/src/components/Hero.tsx`
  - `landing/src/components/FeaturePillars.tsx`
  - `landing/src/components/FloorManagement.tsx`
  - `landing/src/components/PlayStoreBanner.tsx`
  - `landing/src/components/Pricing.tsx`
  - `landing/src/components/Testimonials.tsx`
  - `landing/src/components/FAQ.tsx`
  - `landing/src/components/Footer.tsx`
- **Actions:**
  1. Assemble rich, engaging visual components adhering to the Warm Gourmet Light Mode theme.
  2. Add interactive floor/section switcher (AC Dining, Garden, Bar) with live table occupancy tags.
  3. Add Monthly / Annual billing toggle on Pricing with 20% savings badge.
  4. Implement expandable FAQ accordion.
- **Verification:** Check responsive layout across desktop and mobile viewports.

---

### Task 6: Build Interactive Mini POS Simulator & Demo Booking Modal
- **Files:**
  - `landing/src/components/PosSimulator.tsx`
  - `landing/src/components/DemoModal.tsx`
- **Actions:**
  1. Build the POS simulator:
     - Filter items by category.
     - Add to cart, increment/decrement quantity, delete line items.
     - Compute real-time subtotal, 2.5% CGST + 2.5% SGST (5% GST total), and grand total in ₹.
     - "Simulate Wi-Fi Outage" toggle switch: flips state from Online to Offline, updating badges and explaining local outbox queue.
     - "Fire KOT & Print Bill" button: animates a realistic printed receipt slip with invoice and order number.
  2. Build "Book a Demo" modal:
     - Form fields: Restaurant Name, City, Contact Person, WhatsApp Phone, Format.
     - Validation and submission confirmation ticket.
     - "Chat on WhatsApp" direct link with pre-populated message.
- **Verification:** Test all simulator interactions, cart math, offline switch, and form submission.

---

### Task 7: End-to-End Build & Verification
- **Actions:**
  1. Run `npm run build` in `landing/` to verify zero TypeScript errors and production bundle readiness.
  2. Test route handling for direct policy URLs (`/privacy-policy`, `/terms`, `/data-deletion`).
  3. Validate all interactive elements and responsive styling.
