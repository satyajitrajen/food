// Command seed loads the DEMO dataset (org-01 "Spice Haven", outlets out-01
// Baner and out-02 Kothrud, staff, tables, menu, inventory, suppliers) into a
// development database. It is idempotent (upserts / ON CONFLICT DO NOTHING)
// and refuses to run when FOODPOS_ENV=production. Real tenants are created
// with cmd/admin create-org + import-menu, never with this.
//
//	FOODPOS_DSN=postgres://… go run ./cmd/seed
//
// Demo PINs: admin 0000, manager 9999, cashier 1234, waiter 1111, kitchen 5555
// (Kothrud: manager 8888, cashier 3333, waiter 2222, kitchen 6666). Org code
// HISHOBKR.
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"time"

	"foodpos/backend/internal/auth"
	"foodpos/backend/internal/config"
	"foodpos/backend/internal/db"
	"foodpos/backend/internal/models"
	"foodpos/backend/internal/store"
)

func main() {
	cfg := config.Load()
	if cfg.Env == "production" {
		fmt.Fprintln(os.Stderr, "refusing to seed demo data: FOODPOS_ENV=production")
		os.Exit(1)
	}
	database, err := db.Open(cfg.DSN)
	if err != nil {
		slog.Error("db open failed", "err", err)
		os.Exit(1)
	}
	defer database.Close()
	if err := db.Migrate(database); err != nil {
		slog.Error("migrations failed", "err", err)
		os.Exit(1)
	}
	st := store.New(database)
	if err := Seed(context.Background(), st, auth.New("seed", cfg.BcryptCost)); err != nil {
		slog.Error("seed failed", "err", err)
		os.Exit(1)
	}
	fmt.Println("demo data loaded (org code HISHOBKR)")
}

type seedStaff struct {
	id, name, role, pin, mobile string
	outlet                      any
	protected                   int
}

type seedItem struct {
	id, cat, name, desc string
	paise               int64
	veg, best           bool
	variants            [][2]any // {name, paise}
	groups              []seedGroup
}

type seedGroup struct {
	name  string
	multi bool
	items [][2]any // {name, paise}
}

var (
	staff = []seedStaff{
		{"st-01", "Rahul Sharma", "cashier", "1234", "+91 98220 11223", nil, 0},
		{"st-02", "Priya Joshi", "manager", "9999", "+91 98220 22334", nil, 0},
		{"st-03", "Vikram Singh", "admin", "0000", "+91 98220 33445", nil, 1},
		{"st-04", "Amit Deshmukh", "waiter", "1111", "+91 98220 44556", "out-01", 0},
		{"st-06", "Chef Sharma", "kitchen", "5555", "+91 98220 66778", "out-01", 0},
		{"st-07", "Neha Kulkarni", "manager", "8888", "+91 98220 77889", nil, 0},
		{"st-08", "Suresh Patel", "cashier", "3333", "+91 98220 88990", nil, 0},
		{"st-09", "Kiran More", "waiter", "2222", "+91 98220 99001", "out-02", 0},
		{"st-10", "Sunita Rao", "kitchen", "6666", "+91 98220 10112", "out-02", 0},
	}
	tables = []struct {
		num   string
		seats int
		floor string
	}{
		{"T01", 2, "Ground Floor"}, {"T02", 4, "Ground Floor"}, {"T03", 4, "Ground Floor"},
		{"T04", 6, "Ground Floor"}, {"T05", 4, "Ground Floor"}, {"T06", 4, "Ground Floor"},
		{"T07", 2, "First Floor"}, {"T08", 6, "First Floor"}, {"T09", 8, "First Floor"},
		{"T10", 4, "Outdoor"}, {"T11", 2, "Outdoor"}, {"T12", 4, "Outdoor"},
	}
	categories = []string{"Starters", "Soups", "Main Course", "Biryani", "Chinese", "Pizza", "Drinks", "Desserts"}
	menu       = []seedItem{
		{"m-01", "Starters", "Paneer Tikka", "Marinated cottage cheese char-grilled with capsicum & onions.", 28000, true, true, nil,
			[]seedGroup{
				{"Spice Level", false, [][2]any{{"Medium Spicy", 0}, {"Extra Spicy", 0}, {"Mild / Jain", 0}}},
				{"Add-ons", true, [][2]any{{"Extra Mint Chutney", 2000}, {"Laccha Onions", 1500}, {"Extra Butter Coat", 3000}}},
			}},
		{"m-02", "Starters", "Chicken Tandoori", "Chicken cured in aromatic tandoori masala.", 36000, false, true,
			[][2]any{{"Half (4 pcs)", 24000}, {"Full (8 pcs)", 42000}}, nil},
		{"m-03", "Soups", "Tomato Dhaniya Shorba", "Plum tomato broth with coriander and cumin.", 16000, true, false, nil, nil},
		{"m-04", "Main Course", "Butter Chicken", "Chicken simmered in silky buttery tomato gravy.", 35000, false, true, nil, nil},
		{"m-05", "Main Course", "Dal Makhani", "Black lentils slow cooked with butter and cream.", 24000, true, true, nil, nil},
		{"m-06", "Main Course", "Butter Naan", "Leavened flatbread brushed with salted butter.", 5000, true, false, nil, nil},
		{"m-07", "Biryani", "Veg Dum Biryani", "Basmati layered with garden vegetables and saffron.", 26000, true, false, nil, nil},
		{"m-08", "Biryani", "Chicken Dum Biryani", "Hyderabadi style dum cooked chicken biryani.", 33000, false, true, nil, nil},
		{"m-09", "Pizza", "Margherita Pizza", "Stone-baked with San Marzano tomatoes and mozzarella.", 19900, true, false,
			[][2]any{{"Regular", 19900}, {"Medium", 29900}, {"Large", 39900}},
			[]seedGroup{
				{"Extra Toppings", true, [][2]any{{"Extra Cheese", 5000}, {"Jalapeno", 3000}, {"Mushroom", 4000}}},
				{"Crust & Bake", false, [][2]any{{"Normal Bake", 0}, {"Well Done / Crispy", 0}}},
			}},
		{"m-10", "Chinese", "Crispy Veg Chilli", "Wok tossed vegetables in garlic soya glaze.", 22000, true, false, nil, nil},
		{"m-11", "Drinks", "Fresh Lime Soda", "Fresh lime with soda or water.", 9000, true, false, nil, nil},
		{"m-12", "Desserts", "Gulab Jamun (2 Pcs)", "Milk dumplings in cardamom rose syrup.", 11000, true, false, nil, nil},
	}
	inventory = []struct {
		id, name, unit string
		stock, min     float64
		cost           int64
	}{
		{"inv-1", "Fresh Paneer", "KG", 18, 10, 32000},
		{"inv-2", "Mozzarella Cheese", "KG", 4, 8, 45000},
		{"inv-3", "Basmati Rice", "KG", 45, 25, 11000},
		{"inv-4", "Chicken (Curry Cut)", "KG", 14, 10, 22000},
		{"inv-5", "Cooking Butter", "KG", 3.5, 6, 52000},
		{"inv-6", "Amul Fresh Cream", "Litre", 12, 5, 18000},
	}
	suppliers = []struct {
		id, name, mobile, cat string
		outstanding           int64
	}{
		{"sup-1", "Metro Dairy Farms", "+91 98221 00112", "Dairy & Paneer", 450000},
		{"sup-2", "Agro Fresh Poultry", "+91 98221 00223", "Chicken & Eggs", 280000},
		{"sup-3", "Pune Wholesale Spices", "+91 98221 00334", "Groceries & Rice", 0},
	}
)

// Seed loads the demo dataset idempotently.
func Seed(ctx context.Context, st *store.Store, mgr *auth.Manager) error {
	x := func(q string, args ...any) error {
		_, err := st.DB.ExecContext(ctx, q, args...)
		return err
	}
	now := store.TimeStr(store.Now())
	if err := x(`INSERT INTO organizations (id, name, email, gstin, status, created_at, updated_at)
		VALUES ('org-01', 'Spice Haven (demo)', 'demo@hishobkr.com', '27AAAAA0000A1Z5', 'active', ?, ?)
		ON CONFLICT (id) DO NOTHING`, now, now); err != nil {
		return err
	}
	if err := x(`INSERT INTO org_codes (org_id, code, active, created_at) VALUES ('org-01', 'HISHOBKR', 1, ?)
		ON CONFLICT (code) DO NOTHING`, now); err != nil {
		return err
	}
	outlets := []struct{ id, name, addr, terminal, fssai, phone, suffix string }{
		{"out-01", "Baner Outlet", "Plot 42, High Street, Baner, Pune - 411045", "POS-01", "11521000000123", "+91 98765 43210", ""},
		{"out-02", "Kothrud Outlet", "Shop 12, Paud Road, Kothrud, Pune", "POS-02", "11521000000124", "+91 98765 43211", "-02"},
	}
	for _, o := range outlets {
		if err := x(`INSERT INTO outlets (id, org_id, name, address, terminal, gstin, fssai, phone, timezone, is_online)
			VALUES (?, 'org-01', ?, ?, ?, '27AAAAA0000A1Z5', ?, ?, 'Asia/Kolkata', 1) ON CONFLICT (id) DO NOTHING`,
			o.id, o.name, o.addr, o.terminal, o.fssai, o.phone); err != nil {
			return err
		}
	}
	for _, s := range staff {
		hash, err := mgr.HashPIN(s.pin)
		if err != nil {
			return err
		}
		if err := x(`INSERT INTO staff (id, org_id, outlet_id, name, role, pin_hash, avatar_url, mobile, is_active, is_protected)
			VALUES (?, 'org-01', ?, ?, ?, ?, '', ?, 1, ?) ON CONFLICT (id) DO NOTHING`,
			s.id, s.outlet, s.name, s.role, hash, s.mobile, s.protected); err != nil {
			return err
		}
	}
	for _, o := range outlets {
		if err := seedOutletCatalog(ctx, st, x, o.id, o.suffix, o.name); err != nil {
			return fmt.Errorf("%s: %w", o.id, err)
		}
	}
	// Demo org gets an active subscription so its terminals are entitled.
	if err := st.SeedDefaultPlans(ctx); err != nil {
		return err
	}
	if sub, err := st.GetSubscription(ctx, "org-01"); err != nil || sub == nil {
		plan, err := st.GetPlanByCode(ctx, "pro")
		if err != nil {
			return err
		}
		start := time.Now().UTC()
		end := start.AddDate(1, 0, 0)
		if err := st.UpsertSubscription(ctx, &models.OrgSubscription{OrgID: "org-01", PlanID: plan.ID,
			Status: models.SubActive, CurrentPeriodStart: &start, CurrentPeriodEnd: &end}); err != nil {
			return err
		}
		return st.SetOrgStatus(ctx, "org-01", models.OrgActive)
	}
	return nil
}

func seedOutletCatalog(ctx context.Context, st *store.Store, x func(string, ...any) error, outletID, sfx, name string) error {
	for _, t := range tables {
		if err := x(`INSERT INTO tables (id, outlet_id, table_number, seats, floor, status)
			VALUES (?, ?, ?, ?, ?, 'available') ON CONFLICT DO NOTHING`,
			"t-"+t.num[1:]+sfx, outletID, t.num, t.seats, t.floor); err != nil {
			return err
		}
	}
	catID := map[string]string{}
	for i, c := range categories {
		id, err := st.CategoryID(ctx, outletID, c)
		if err != nil {
			return err
		}
		if err := st.SetCategorySort(ctx, id, i); err != nil {
			return err
		}
		catID[c] = id
	}
	for i, m := range menu {
		id := m.id + sfx
		if err := x(`INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
			VALUES (?, ?, ?, ?, ?, ?, ?, '', ?, 1, ?) ON CONFLICT DO NOTHING`,
			id, outletID, catID[m.cat], m.name, m.desc, m.paise, m.veg, m.best, i); err != nil {
			return err
		}
		for vi, v := range m.variants {
			if err := x(`INSERT INTO product_variants (id, menu_item_id, name, price_paise) VALUES (?, ?, ?, ?) ON CONFLICT DO NOTHING`,
				fmt.Sprintf("v-%s-%d", id, vi), id, v[0], v[1]); err != nil {
				return err
			}
		}
		for gi, g := range m.groups {
			gid := fmt.Sprintf("mg-%s-%d", id, gi)
			if err := x(`INSERT INTO modifier_groups (id, menu_item_id, name, is_multi_select, is_required, sort)
				VALUES (?, ?, ?, ?, 0, ?) ON CONFLICT DO NOTHING`, gid, id, g.name, g.multi, gi); err != nil {
				return err
			}
			for ii, mi := range g.items {
				if err := x(`INSERT INTO modifier_items (id, group_id, name, price_paise, sort) VALUES (?, ?, ?, ?, ?) ON CONFLICT DO NOTHING`,
					fmt.Sprintf("mo-%s-%d-%d", id, gi, ii), gid, mi[0], mi[1], ii); err != nil {
					return err
				}
			}
		}
	}
	if err := x(`INSERT INTO settings (outlet_id, restaurant_name, gst_percent, is_gst_inclusive, service_percent,
		packaging_paise, delivery_paise, auto_print_kot, allow_reprint, billing_printer, kitchen_printer, bar_printer, sections)
		VALUES (?, ?, 5.0, 0, 0, 2500, 4000, 1, 1, '', '', '', '["Ground Floor","First Floor","Outdoor"]')
		ON CONFLICT DO NOTHING`, outletID, "Spice Haven - "+name); err != nil {
		return err
	}
	for _, it := range inventory {
		if err := x(`INSERT INTO inventory_items (id, outlet_id, name, unit, stock, min_stock, cost_paise)
			VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT DO NOTHING`, it.id+sfx, outletID, it.name, it.unit, it.stock, it.min, it.cost); err != nil {
			return err
		}
	}
	for _, sp := range suppliers {
		if err := x(`INSERT INTO suppliers (id, outlet_id, name, mobile, category, outstanding)
			VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT DO NOTHING`, sp.id+sfx, outletID, sp.name, sp.mobile, sp.cat, sp.outstanding); err != nil {
			return err
		}
	}
	return nil
}
