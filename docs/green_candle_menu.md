# Hotel Green Candle — Page 1 Menu Integration

**Outlet:** `out-green-candle` — Hotel Green Candle  
**Address:** Hotel Green Candle, Main Road, Maharashtra  
**Terminal:** POS-GC-01 | Phone: +91 98765 43212  
**GSTIN:** 27AAAAA0000A1Z5 | FSSAI: 11521000000125

---

## Summary

Complete **Page 1 menu (57 items)** from the scanned Hotel Green Candle menu has been integrated into:

| Layer | File / Endpoint | Details |
|-------|----------------|---------|
| **Flutter offline menu** | `lib/providers/pos_provider.dart` | 57 `MenuItem`s with `outletId: 'out-green-candle'`, variants for Half/Full etc., visible only when Green Candle outlet is selected |
| **Outlet definition** | `PosProvider._outlets` | Added `out-green-candle` to outlet list |
| **Staff** | `PosProvider._staffList` | 4 dedicated staff: Manager 7777, Cashier 4444, Waiter 1212, Kitchen 3434 |
| **CSV (full)** | `assets/green_candle_menu.csv` | Category, Marathi, English, Half, Full, Variants, Bestseller, VEG, Description |
| **CSV (POS-simple)** | `assets/green_candle_pos.csv` | Category | Item | Half Price | Full Price — directly importable to POS |
| **Excel** | `assets/green_candle_menu.xlsx` | Styled workbook with filters, alternating rows, printable landscape |
| **JSON (API)** | `assets/green_candle_menu.json` | `price_paise` + variants, ready for `POST /api/v1/menu?outlet_id=out-green-candle` |
| **Backend SQL seed** | `backend/scripts/seed_green_candle.sql` | Idempotent `INSERT` for outlet, categories, 57 items+variants, staff, settings, 12 tables |
| **Backend Go seeder** | `backend/scripts/seed_green_candle.go` | `go run backend/scripts/seed_green_candle.go` — reads JSON, uses `CategoryID` resolver |
| **Live API script** | `tool/seed_green_candle_api.sh` | Curl+Python loop against `https://food.nexorytechnologies.com` |

All 9 Marathi categories are preserved in Unicode:

- अरख्खा मसूर स्पेशल (3 items)
- दाल फ्राय स्पेशल (2)
- इंडियन व्हेज स्पेशल (10)
- काजू स्पेशल (4)
- व्हेज स्पेशल (10) — includes **ग्रीन कँडल स्पेशल ₹299 ★ bestseller**
- राईस स्पेशल (9)
- रोटी स्पेशल (9)
- थंडाई स्पेशल (4)
- पापड स्पेशल (6)

---

## Variant Design

Items with **Half/Full** (e.g. स्पेशल अरख्खा मसूर) → one `MenuItem` with two `ProductVariant`s:

```dart
MenuItem(
  id: 'gc-01',
  outletId: 'out-green-candle',
  name: 'स्पेशल अरख्खा मसूर',
  category: 'अरख्खा मसूर स्पेशल',
  price: 100.0, // Full price as default
  variants: [
    ProductVariant(id: 'v-gc-01-half', name: 'Half', price: 60),
    ProductVariant(id: 'v-gc-01-full', name: 'Full', price: 100),
  ],
)
```

Roti with **साधी/बटर**, Solkadhi with **Glass/Liter**, Kulcha with **रेग्युलर/बटर** follow the same pattern.

Item price in `price_paise` = Full variant ×100. Single-price items have `price_paise` and no `variants` array.

---

## How to Use

### 1) Flutter (offline/demo)

Select outlet **Hotel Green Candle** from the outlet picker.
Categories auto-rebuild to Marathi names. All 57 items appear under their category. Variants open in the `VariantAndModifiersDialog`.

### 2) Backend — SQL seed (psql)

```bash
export DATABASE_URL="postgres://foodpos:foodpos@localhost/foodpos?sslmode=disable"
psql $DATABASE_URL -f backend/scripts/seed_green_candle.sql
```

Idempotent — safe to re-run. Replace `'org-01'` if your org differs.

### 3) Backend — Go seed

```bash
go run backend/scripts/seed_green_candle.go
# env: DATABASE_URL or FOODPOS_DSN, GC_ORG_ID=org-01
```

Hashes staff PINs with bcrypt via `auth.Manager`. Reads `assets/green_candle_menu.json`.

### 4) Live server — API

```bash
# Local dev
./tool/seed_green_candle_api.sh http://localhost:8080 st-02 9999 out-green-candle

# Production
./tool/seed_green_candle_api.sh https://food.nexorytechnologies.com st-02 9999 out-green-candle
```

Verifies via:
- Customer QR menu: `GET /m/out-green-candle`
- Admin API: `GET /api/v1/menu?outlet_id=out-green-candle` (Bearer token)

### 5) POS import — CSV/Excel

- **Detailed CSV:** `assets/green_candle_menu.csv` (UTF-8 BOM, opens in Excel/Google Sheets)
- **Simple POS CSV:** `assets/green_candle_pos.csv` → `Category | Item | Half Price | Full Price`
- **Excel workbook:** `assets/green_candle_menu.xlsx` — filtered, styled, printable, “BESTSELLER” flagged with ★

Open the Excel → **Data → Filter** enabled, frozen header, landscape A4, ready to print for counter/menu card.

---

## PINs for Green Candle Staff (demo/offline)

| Role | Name | PIN | Outlet |
|------|------|-----|--------|
| Manager | Green Candle Manager | 7777 | out-green-candle |
| Cashier | Green Candle Cashier | 4444 | out-green-candle |
| Waiter | Green Candle Waiter | 1212 | out-green-candle |
| Kitchen | Green Candle Kitchen | 3434 | out-green-candle |

Admin `st-03 / 0000` is org-wide and can access any outlet.

---

## Notes & Decisions

- **Half/Full merging:** Original page lists Half and Full as separate lines (e.g. स्पेशल अरख्खा मसूर Full ₹100 + Half ₹60). Merged into one item with variants for cleaner KOT and billing. If you prefer two separate SKUs, set variant price to 0 and create two `MenuItem`s — but variants are the POS standard.
- **Lasun Tadka Half:** Page shows “अरख्खा मसूर लसूण तडका — ₹120” followed by “लसूण तडका — Half ₹70”. Interpreted as same dish with Half ₹70 / Full ₹120 variants.
- **Veg-only:** All items marked `isVeg: true`. If any non-veg items exist on later pages, set `isVeg: false` per item.
- **Pricing in paise:** Backend stores `price_paise` (₹×100). Frontend `price` is rupees (`double`).
- **Images:** Placeholder Unsplash `photo-1504674900247…` — replace with dish photos via **Menu Admin → Upload** (POST `/api/v1/uploads/menu-image`).
- **Tables:** SQL seed creates 12 tables `GC-01 … GC-12` scoped to `out-green-candle` across Ground/First/Outdoor. Flutter offline tables are shared (no `outletId` field) — first offline launch shows existing 12 tables; server-hydrated tables are outlet-scoped correctly.

---

## Page 1 Raw — For Reference

> अरख्खा मसूर स्पेशल, दाल फ्राय स्पेशल, इंडियन व्हेज स्पेशल, काजू स्पेशल, व्हेज स्पेशल, राईस स्पेशल, रोटी स्पेशल, थंडाई स्पेशल, पापड स्पेशल सॅक्स — 57 items with variants.

Full transliteration and pricing in `assets/green_candle_menu.csv` (column C = English).

---

## Next Steps

- Page 2+ menu? Append new categories/items to the same files (keep `gc-58` onward).
- Replace placeholder images with real dish photos.
- Adjust GST/tax in Settings → `PUT /api/v1/settings?outlet_id=out-green-candle` (default 5% exclusive).
- Print Excel for kitchen display and QR table cards (`/m/out-green-candle`).

Generated: 2026-09-23 | Source: `assets/green_candle_menu.json/.csv/.xlsx`
