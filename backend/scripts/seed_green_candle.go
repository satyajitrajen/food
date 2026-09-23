
package main

// Seeds Hotel Green Candle menu (page 1) into an outlet.
// Usage: go run backend/scripts/seed_green_candle.go
// Env: DATABASE_URL or FOODPOS_DSN (defaults to postgres://foodpos:foodpos@localhost/foodpos?sslmode=disable)
// Set GC_ORG_ID if your org is not org-01.

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"os"

	_ "github.com/lib/pq"
	"foodpos/backend/internal/auth"
	"foodpos/backend/internal/db"
	"foodpos/backend/internal/store"
)

func main() {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = os.Getenv("FOODPOS_DSN")
	}
	if dsn == "" {
		dsn = "postgres://foodpos:foodpos@localhost/foodpos?sslmode=disable"
	}
	orgID := os.Getenv("GC_ORG_ID")
	if orgID == "" {
		orgID = "org-01"
	}
	outletID := "out-green-candle"
	dbConn, err := db.Open(dsn)
	if err != nil {
		log.Fatalf("open db: %v", err)
	}
	defer dbConn.Close()
	if err := db.Migrate(dbConn); err != nil {
		log.Fatalf("migrate: %v", err)
	}
	st := store.New(dbConn)
	ctx := context.Background()
	mgr := auth.New("seed-secret", 4)

	// 1) Ensure outlet
	_ = ensureOutlet(ctx, dbConn, orgID, outletID)

	// 2) Ensure staff (hash pins)
	for _, s := range []struct{ id, name, role, pin string }{
		{"st-gc-01", "Green Candle Manager", "manager", "7777"},
		{"st-gc-02", "Green Candle Cashier", "cashier", "4444"},
		{"st-gc-03", "Green Candle Waiter", "waiter", "1212"},
		{"st-gc-04", "Green Candle Kitchen", "kitchen", "3434"},
	} {
		hash, _ := mgr.HashPIN(s.pin)
		_, _ = dbConn.ExecContext(ctx, `INSERT INTO staff (id, org_id, outlet_id, name, role, pin_hash, is_active, is_protected)
			VALUES ($1,$2,$3,$4,$5,$6,1,0) ON CONFLICT (id) DO UPDATE SET pin_hash=EXCLUDED.pin_hash, name=EXCLUDED.name`, s.id, orgID, outletID, s.name, s.role, hash)
	}

	// 3) Menu JSON (embedded path)
	jsonPath := "assets/green_candle_menu.json"
	if _, err := os.Stat(jsonPath); os.IsNotExist(err) {
		jsonPath = "backend/../assets/green_candle_menu.json"
	}
	raw, err := os.ReadFile(jsonPath)
	if err != nil {
		// fallback to executable-relative path
		raw, err = os.ReadFile("/root/food/assets/green_candle_menu.json")
		if err != nil {
			log.Fatalf("read menu json: %v", err)
		}
	}
	var items []map[string]any
	if err := json.Unmarshal(raw, &items); err != nil {
		log.Fatalf("json: %v", err)
	}
	for _, it := range items {
		name, _ := it["name"].(string)
		cat, _ := it["category_id"].(string)
		price, _ := it["price_paise"].(float64)
		// CategoryID will auto-create
		catID, err := st.CategoryID(ctx, outletID, cat)
		if err != nil {
			log.Fatalf("category %q: %v", cat, err)
		}
		// Build upsert payload
		isVeg, _ := it["is_veg"].(bool)
		desc, _ := it["description"].(string)
		best, _ := it["is_bestseller"].(bool)
		img, _ := it["image_url"].(string)
		localID, _ := it["local_id"].(string)
		// Variants
		var variants []map[string]any
		if v, ok := it["variants"].([]any); ok {
			for _, vv := range v {
				m := vv.(map[string]any)
				variants = append(variants, map[string]any{"name": m["name"], "price_paise": m["price_paise"]})
			}
		}
		// Use store path: delete + recreate if exists to make idempotent
		_ = localID
		_ = price
		// Insert via Store.CreateMenuItem (idempotent via local_id check)
		// We shell out to direct SQL for deterministic ids to keep GC ids stable
		_ = best
		_ = isVeg
		_ = desc
		_ = img
		// For determinism, insert directly
		var exists string
		err = dbConn.QueryRowContext(ctx, `SELECT id FROM menu_items WHERE id=$1`, localID).Scan(&exists)
		if err == sql.ErrNoRows {
			bo := best
			iv := isVeg
			pp := int64(price)
			// use the store's CreateMenuItem with the real category id
			req := struct {
				CategoryID     *string `json:"category_id"`
				Name           *string `json:"name"`
				Description    *string `json:"description"`
				PricePaise     *int64  `json:"price_paise"`
				IsVeg          *bool   `json:"is_veg"`
				ImageURL       *string `json:"image_url"`
				IsBestseller   *bool   `json:"is_bestseller"`
			}{CategoryID: &catID, Name: &name, Description: &desc, PricePaise: &pp, IsVeg: &iv, ImageURL: &img, IsBestseller: &bo}
			// We use a low-level insert to preserve the GC id
			_, _ = req, localID // placeholder to avoid unused
			// Direct insert to keep custom id
			_, err = dbConn.ExecContext(ctx, `INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,1) ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller`,
				localID, outletID, catID, name, desc, int64(price), boolToInt(isVeg), img, boolToInt(best))
			if err != nil {
				log.Printf("insert %s: %v", name, err)
				continue
			}
			for _, vv := range variants {
				_, _ = dbConn.ExecContext(ctx, `INSERT INTO product_variants (id, menu_item_id, name, price_paise) VALUES ($1,$2,$3,$4)`, fmt.Sprintf("v-%s-%s", localID, vv["name"]), localID, vv["name"], vv["price_paise"])
			}
		}
		log.Printf("seeded %s (%s) %v", name, cat, price)
	}
	fmt.Println("Hotel Green Candle seed complete for outlet", outletID)
}

func ensureOutlet(ctx context.Context, dbConn *sql.DB, orgID, outletID string) error {
	_, err := dbConn.ExecContext(ctx, `INSERT INTO outlets (id, org_id, name, address, terminal, gstin, fssai, phone, is_online) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,1)
		ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, address=EXCLUDED.address`, outletID, orgID, "Hotel Green Candle", "Hotel Green Candle, Main Road, Maharashtra", "POS-GC-01", "27AAAAA0000A1Z5", "11521000000125", "+91 98765 43212")
	return err
}
func boolToInt(b bool) int { if b { return 1 }; return 0 }
