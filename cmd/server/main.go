// FoodPOS server entrypoint: config → db → seed → routes → listen.
package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"foodpos/backend/internal/api"
	"foodpos/backend/internal/auth"
	"foodpos/backend/internal/config"
	"foodpos/backend/internal/db"
	"foodpos/backend/internal/store"
	"foodpos/backend/internal/ws"
)

func main() {
	cfg := config.Load()
	slog.Info("foodpos server starting", "port", cfg.Port, "dsn", cfg.DSN)

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
	authMgr := auth.New(cfg.JWTSecret, cfg.BcryptCost)
	hub := ws.NewHub(authMgr)
	tickets := auth.NewTicketStore(auth.SSETicketTTL)
	hub.SetTicketStore(tickets)

	if cfg.Seed {
		if err := seed(st, authMgr); err != nil {
			slog.Error("seed failed", "err", err)
			os.Exit(1)
		}
		slog.Info("seed data loaded")
	}

	srv := &api.Server{Store: st, Auth: authMgr, Hub: hub, Tickets: tickets, Cfg: cfg}

	httpSrv := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           srv.Routes(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	go func() {
		slog.Info("listening", "addr", httpSrv.Addr)
		if err := httpSrv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("listen failed", "err", err)
			os.Exit(1)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop
	slog.Info("shutting down")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = httpSrv.Shutdown(ctx)
}

// seed loads demo data mirroring the Flutter prototype so the app is
// instantly usable (FOODPOS_SEED=1).
func seed(st *store.Store, mgr *auth.Manager) error {
	ctx := context.Background()

	// Outlets
	_, err := st.DB.ExecContext(ctx, `INSERT INTO outlets (id, name, address, terminal, gstin, fssai, phone, is_online)
		VALUES ('out-01', 'Baner Outlet', 'Plot 42, High Street, Baner, Pune - 411045', 'POS-01', '27AAAAA0000A1Z5', '11521000000123', '+91 98765 43210', 1) ON CONFLICT DO NOTHING`)
	if err != nil {
		return err
	}
	_, err = st.DB.ExecContext(ctx, `INSERT INTO outlets (id, name, address, terminal, gstin, fssai, phone, is_online)
		VALUES ('out-02', 'Kothrud Outlet', 'Shop 12, Paud Road, Kothrud, Pune', 'POS-02', '27AAAAA0000A1Z5', '11521000000124', '+91 98765 43211', 1) ON CONFLICT DO NOTHING`)
	if err != nil {
		return err
	}

	// Staff (PINs: admin 0000, manager 9999, cashier 1234, waiters 1111/2222, kitchen 5555)
	staff := []struct{ id, name, role, pin, avatar, mobile string }{
		{"st-01", "Rahul Sharma", "cashier", "1234", "https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=100", "+91 98220 11223"},
		{"st-02", "Priya Joshi", "manager", "9999", "https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=100", "+91 98220 22334"},
		{"st-03", "Vikram Singh", "admin", "0000", "https://images.unsplash.com/photo-1570295999919-56ceb5ecca61?w=100", "+91 98220 33445"},
		{"st-04", "Amit Deshmukh", "waiter", "1111", "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=100", "+91 98220 44556"},
		{"st-05", "Rohan Patil", "waiter", "2222", "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=100", "+91 98220 55667"},
		{"st-06", "Chef Sharma", "kitchen", "5555", "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=100", "+91 98220 66778"},
	}
	for _, s := range staff {
		hash, err := mgr.HashPIN(s.pin)
		if err != nil {
			return err
		}
		if _, err := st.DB.ExecContext(ctx, `INSERT INTO staff (id, name, role, pin_hash, avatar_url, mobile, is_active)
			VALUES (?, ?, ?, ?, ?, ?, 1) ON CONFLICT DO NOTHING`, s.id, s.name, s.role, hash, s.avatar, s.mobile); err != nil {
			return err
		}
	}

	// Tables
	tables := []struct {
		id, num string
		seats   int
		floor   string
	}{
		{"t-01", "T01", 2, "Ground Floor"}, {"t-02", "T02", 4, "Ground Floor"},
		{"t-03", "T03", 4, "Ground Floor"}, {"t-04", "T04", 6, "Ground Floor"},
		{"t-05", "T05", 4, "Ground Floor"}, {"t-06", "T06", 4, "Ground Floor"},
		{"t-07", "T07", 2, "First Floor"}, {"t-08", "T08", 6, "First Floor"},
		{"t-09", "T09", 8, "First Floor"}, {"t-10", "T10", 4, "Outdoor"},
		{"t-11", "T11", 2, "Outdoor"}, {"t-12", "T12", 4, "Outdoor"},
	}
	for _, t := range tables {
		if _, err := st.DB.ExecContext(ctx, `INSERT INTO tables (id, outlet_id, table_number, seats, floor, status)
			VALUES (?, 'out-01', ?, ?, ?, 'available') ON CONFLICT DO NOTHING`, t.id, t.num, t.seats, t.floor); err != nil {
			return err
		}
	}

	// Categories + menu with variants/modifiers
	cats := []struct{ id, name string }{
		{"cat-st", "Starters"}, {"cat-so", "Soups"}, {"cat-mc", "Main Course"},
		{"cat-bi", "Biryani"}, {"cat-ch", "Chinese"}, {"cat-pz", "Pizza"},
		{"cat-dr", "Drinks"}, {"cat-de", "Desserts"},
	}
	for i, c := range cats {
		if _, err := st.DB.ExecContext(ctx, `INSERT INTO menu_categories (id, outlet_id, name, sort)
			VALUES (?, 'out-01', ?, ?) ON CONFLICT DO NOTHING`, c.id, c.name, i); err != nil {
			return err
		}
	}

	menu := []struct {
		id, cat, name, desc string
		paise               int64
		veg, best           bool
		img                 string
		variants            []struct {
			name  string
			paise int64
		}
		mods []struct {
			name  string
			multi bool
			items []struct {
				name  string
				paise int64
			}
		}
	}{
		{"m-01", "cat-st", "Paneer Tikka", "Marinated cottage cheese char-grilled with capsicum & onions.", 28000, true, true,
			"https://images.unsplash.com/photo-1599488615731-7e5c2823ff28?w=300",
			nil,
			[]struct {
				name  string
				multi bool
				items []struct {
					name  string
					paise int64
				}
			}{
				{"Spice Level", false, []struct {
					name  string
					paise int64
				}{{"Medium Spicy", 0}, {"Extra Spicy", 0}, {"Mild / Jain", 0}}},
				{"Add-ons", true, []struct {
					name  string
					paise int64
				}{{"Extra Mint Chutney", 2000}, {"Laccha Onions", 1500}, {"Extra Butter Coat", 3000}}},
			}},
		{"m-02", "cat-st", "Chicken Tandoori", "Whole chicken cut pieces cured in aromatic tandoori masala.", 36000, false, true,
			"https://images.unsplash.com/photo-1599488615731-7e5c2823ff28?w=300",
			[]struct {
				name  string
				paise int64
			}{{"Half (4 pcs)", 24000}, {"Full (8 pcs)", 42000}},
			nil},
		{"m-03", "cat-so", "Tomato Dhaniya Shorba", "Fresh plum tomato broth spiced with fresh coriander and cumin.", 16000, true, false,
			"https://images.unsplash.com/photo-1547592166-23ac45744acd?w=300", nil, nil},
		{"m-04", "cat-mc", "Butter Chicken", "Slow-cooked chicken pieces simmered in silky buttery tomato gravy.", 35000, false, true,
			"https://images.unsplash.com/photo-1603894584373-5ac82b2ae398?w=300", nil, nil},
		{"m-05", "cat-mc", "Dal Makhani", "Black lentils overnight slow cooked with butter and fresh cream.", 24000, true, true,
			"https://images.unsplash.com/photo-1546833999-b9f581a1996d?w=300", nil, nil},
		{"m-06", "cat-mc", "Butter Naan", "Crisp, pillowy leavened flatbread brushed with salted butter.", 5000, true, false,
			"https://images.unsplash.com/photo-1601050690597-df0568f70950?w=300", nil, nil},
		{"m-07", "cat-bi", "Veg Dum Biryani", "Long grain basmati rice layered with garden vegetables and saffron.", 26000, true, false,
			"https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=300", nil, nil},
		{"m-08", "cat-bi", "Chicken Dum Biryani", "Hyderabadi style slow dum cooked aromatic chicken biryani.", 33000, false, true,
			"https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=300", nil, nil},
		{"m-09", "cat-pz", "Margherita Pizza", "Classic stone-baked sourdough with San Marzano tomatoes and mozzarella.", 19900, true, false,
			"https://images.unsplash.com/photo-1604382354936-07c5d9983bd3?w=300",
			[]struct {
				name  string
				paise int64
			}{{"Regular", 19900}, {"Medium", 29900}, {"Large", 39900}},
			[]struct {
				name  string
				multi bool
				items []struct {
					name  string
					paise int64
				}
			}{
				{"Extra Toppings", true, []struct {
					name  string
					paise int64
				}{{"Extra Cheese", 5000}, {"Jalapeno", 3000}, {"Mushroom", 4000}, {"Black Olives", 3500}}},
				{"Crust & Bake", false, []struct {
					name  string
					paise int64
				}{{"Normal Bake", 0}, {"Well Done / Crispy", 0}}},
			}},
		{"m-10", "cat-ch", "Crispy Veg Chilli", "Crisp wok tossed exotic vegetables in dark garlic soya glaze.", 22000, true, false,
			"https://images.unsplash.com/photo-1585032226651-759b368d7246?w=300", nil, nil},
		{"m-11", "cat-dr", "Fresh Lime Soda", "Fresh squeezed lime with soda or water (Sweet/Salt/Mix).", 9000, true, false,
			"https://images.unsplash.com/photo-1513558161293-cdaf765ed2fd?w=300", nil, nil},
		{"m-12", "cat-de", "Gulab Jamun (2 Pcs)", "Warm golden milk dumplings soaked in fragrant cardamom rose syrup.", 11000, true, false,
			"https://images.unsplash.com/photo-1541781774459-bb2af2f05b55?w=300", nil, nil},
	}
	for i, m := range menu {
		if _, err := st.DB.ExecContext(ctx, `INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
			VALUES (?, 'out-01', ?, ?, ?, ?, ?, ?, ?, 1, ?) ON CONFLICT DO NOTHING`,
			m.id, m.cat, m.name, m.desc, m.paise, b2i(m.veg), m.img, b2i(m.best), i); err != nil {
			return err
		}
		for vi, v := range m.variants {
			if _, err := st.DB.ExecContext(ctx, `INSERT INTO product_variants (id, menu_item_id, name, price_paise)
				VALUES (?, ?, ?, ?) ON CONFLICT DO NOTHING`, fmt.Sprintf("v-%s-%d", m.id, vi), m.id, v.name, v.paise); err != nil {
				return err
			}
		}
		for gi, g := range m.mods {
			gid := fmt.Sprintf("mg-%s-%d", m.id, gi)
			if _, err := st.DB.ExecContext(ctx, `INSERT INTO modifier_groups (id, menu_item_id, name, is_multi_select, is_required, sort)
				VALUES (?, ?, ?, ?, 0, ?) ON CONFLICT DO NOTHING`, gid, m.id, g.name, b2i(g.multi), gi); err != nil {
				return err
			}
			for ii, mi := range g.items {
				if _, err := st.DB.ExecContext(ctx, `INSERT INTO modifier_items (id, group_id, name, price_paise, sort)
					VALUES (?, ?, ?, ?, ?) ON CONFLICT DO NOTHING`, fmt.Sprintf("mo-%s-%d-%d", m.id, gi, ii), gid, mi.name, mi.paise, ii); err != nil {
					return err
				}
			}
		}
	}

	// Settings
	_, err = st.DB.ExecContext(ctx, `INSERT INTO settings (outlet_id, restaurant_name, gst_percent, is_gst_inclusive,
		service_percent, packaging_paise, delivery_paise, auto_print_kot, allow_reprint, billing_printer, kitchen_printer, bar_printer, sections)
		VALUES ('out-01', 'Spice Haven Resto & Bar', 5.0, 0, 5.0, 2500, 4000, 1, 1,
		'EPSON TM-T88VI (Counter)', 'TVS RP3200 (Main Kitchen)', 'STAR Micronics (Bar Counter)', '["Ground Floor","First Floor","Outdoor"]') ON CONFLICT DO NOTHING`)
	if err != nil {
		return err
	}

	// Inventory
	inv := []struct {
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
	for _, i := range inv {
		if _, err := st.DB.ExecContext(ctx, `INSERT INTO inventory_items (id, outlet_id, name, unit, stock, min_stock, cost_paise)
			VALUES (?, 'out-01', ?, ?, ?, ?, ?) ON CONFLICT DO NOTHING`, i.id, i.name, i.unit, i.stock, i.min, i.cost); err != nil {
			return err
		}
	}

	// Suppliers
	sup := []struct {
		id, name, mobile, cat string
		outstanding           int64
	}{
		{"sup-1", "Metro Dairy Farms", "+91 98221 00112", "Dairy & Paneer", 450000},
		{"sup-2", "Agro Fresh Poultry", "+91 98221 00223", "Chicken & Eggs", 280000},
		{"sup-3", "Pune Wholesale Spices", "+91 98221 00334", "Groceries & Rice", 0},
	}
	for _, sp := range sup {
		if _, err := st.DB.ExecContext(ctx, `INSERT INTO suppliers (id, outlet_id, name, mobile, category, outstanding)
			VALUES (?, 'out-01', ?, ?, ?, ?) ON CONFLICT DO NOTHING`, sp.id, sp.name, sp.mobile, sp.cat, sp.outstanding); err != nil {
			return err
		}
	}
	return nil
}

func b2i(b bool) int {
	if b {
		return 1
	}
	return 0
}
