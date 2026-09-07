package store

import (
	"context"
	"database/sql"
	"strings"

	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/models"
)

// ---- Outlets ----

func (s *Store) ListOutlets(ctx context.Context) ([]models.Outlet, error) {
	rows, err := s.DB.QueryContext(ctx, `SELECT id, name, address, terminal, gstin, fssai, phone, is_online FROM outlets ORDER BY name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []models.Outlet
	for rows.Next() {
		var o models.Outlet
		var online int
		if err := rows.Scan(&o.ID, &o.Name, &o.Address, &o.Terminal, &o.GSTIN, &o.FSSAI, &o.Phone, &online); err != nil {
			return nil, err
		}
		o.IsOnline = online == 1
		out = append(out, o)
	}
	return out, rows.Err()
}

func (s *Store) GetOutlet(ctx context.Context, id string) (*models.Outlet, error) {
	var o models.Outlet
	var online int
	err := s.DB.QueryRowContext(ctx, `SELECT id, name, address, terminal, gstin, fssai, phone, is_online FROM outlets WHERE id = ?`, id).
		Scan(&o.ID, &o.Name, &o.Address, &o.Terminal, &o.GSTIN, &o.FSSAI, &o.Phone, &online)
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	o.IsOnline = online == 1
	return &o, nil
}

// ---- Staff ----

type StaffRow struct {
	models.Staff
	PINHash string
}

func (s *Store) ListStaff(ctx context.Context) ([]models.Staff, error) {
	rows, err := s.DB.QueryContext(ctx, `SELECT id, name, role, avatar_url, mobile, is_active FROM staff WHERE is_active = 1 ORDER BY name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []models.Staff
	for rows.Next() {
		var st models.Staff
		var active int
		if err := rows.Scan(&st.ID, &st.Name, &st.Role, &st.AvatarURL, &st.Mobile, &active); err != nil {
			return nil, err
		}
		st.IsActive = active == 1
		out = append(out, st)
	}
	return out, rows.Err()
}

func (s *Store) GetStaff(ctx context.Context, id string) (*StaffRow, error) {
	var st StaffRow
	var active int
	err := s.DB.QueryRowContext(ctx, `SELECT id, name, role, avatar_url, mobile, is_active, pin_hash FROM staff WHERE id = ?`, id).
		Scan(&st.ID, &st.Name, &st.Role, &st.AvatarURL, &st.Mobile, &active, &st.PINHash)
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	st.IsActive = active == 1
	return &st, nil
}

func (s *Store) CreateStaff(ctx context.Context, st models.StaffCreate, pinHash string) (*models.Staff, error) {
	id := NewID("st")
	_, err := s.DB.ExecContext(ctx,
		`INSERT INTO staff (id, name, role, pin_hash, avatar_url, mobile, is_active) VALUES (?, ?, ?, ?, ?, ?, 1)`,
		id, st.Name, st.Role, pinHash, st.AvatarURL, st.Mobile)
	if err != nil {
		return nil, err
	}
	row, err := s.GetStaff(ctx, id)
	if err != nil {
		return nil, err
	}
	return &row.Staff, nil
}

// ---- Tables ----

const tableCols = `id, outlet_id, table_number, seats, floor, status, active_order_id, current_amount, running_minutes, guest_count, assigned_waiter_id, merged_with_table_id`

func scanTable(sc interface{ Scan(...any) error }) (*models.Table, error) {
	var t models.Table
	var active, waiter, merged sql.NullString
	var amount int64
	if err := sc.Scan(&t.ID, &t.OutletID, &t.TableNumber, &t.Seats, &t.Floor, &t.Status,
		&active, &amount, &t.RunningMinutes, &t.GuestCount, &waiter, &merged); err != nil {
		return nil, err
	}
	if active.Valid {
		t.ActiveOrderID = &active.String
	}
	t.CurrentAmount = amount
	if waiter.Valid {
		t.AssignedWaiterID = &waiter.String
	}
	if merged.Valid {
		t.MergedWithTableID = &merged.String
	}
	return &t, nil
}

func (s *Store) ListTables(ctx context.Context, outletID, floor string) ([]models.Table, error) {
	q := `SELECT ` + tableCols + ` FROM tables WHERE outlet_id = ?`
	args := []any{outletID}
	if floor != "" && floor != "All" {
		q += ` AND floor = ?`
		args = append(args, floor)
	}
	q += ` ORDER BY table_number`
	rows, err := s.DB.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []models.Table
	for rows.Next() {
		t, err := scanTable(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *t)
	}
	return out, rows.Err()
}

func (s *Store) GetTable(ctx context.Context, id string) (*models.Table, error) {
	row := s.DB.QueryRowContext(ctx, `SELECT `+tableCols+` FROM tables WHERE id = ?`, id)
	t, err := scanTable(row)
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	return t, err
}

func (s *Store) CreateTable(ctx context.Context, t models.Table) (*models.Table, error) {
	id := NewID("t")
	_, err := s.DB.ExecContext(ctx,
		`INSERT INTO tables (id, outlet_id, table_number, seats, floor, status) VALUES (?, ?, ?, ?, ?, 'available')`,
		id, t.OutletID, t.TableNumber, t.Seats, t.Floor)
	if err != nil {
		return nil, err
	}
	return s.GetTable(ctx, id)
}

func (s *Store) PatchTable(ctx context.Context, id string, p models.TablePatch) (*models.Table, error) {
	t, err := s.GetTable(ctx, id)
	if err != nil {
		return nil, err
	}
	if p.Status != nil {
		st := strings.ToLower(*p.Status)
		switch st {
		case "available", "occupied", "reserved", "billing", "cleaning":
			if _, err := s.DB.ExecContext(ctx, `UPDATE tables SET status = ? WHERE id = ?`, st, id); err != nil {
				return nil, err
			}
		default:
			return nil, httpx.NewError(400, "invalid_status", "Unknown table status")
		}
	}
	if p.GuestCount != nil {
		if _, err := s.DB.ExecContext(ctx, `UPDATE tables SET guest_count = ? WHERE id = ?`, *p.GuestCount, id); err != nil {
			return nil, err
		}
	}
	if p.WaiterID != nil {
		if _, err := s.DB.ExecContext(ctx, `UPDATE tables SET assigned_waiter_id = ? WHERE id = ?`, *p.WaiterID, id); err != nil {
			return nil, err
		}
	}
	_ = t
	return s.GetTable(ctx, id)
}

// ---- Menu ----

func (s *Store) ListCategories(ctx context.Context, outletID string) ([]models.ModifierGroup, error) {
	return nil, nil // categories fetched as part of menu below
}

func (s *Store) ListMenu(ctx context.Context, outletID, categoryID string) ([]models.MenuItem, error) {
	q := `SELECT mi.id, mi.outlet_id, mi.category_id, COALESCE(mc.name,''), mi.name, mi.description, mi.price_paise,
	             mi.is_veg, mi.image_url, mi.is_bestseller, mi.is_available, mi.sort
	      FROM menu_items mi LEFT JOIN menu_categories mc ON mc.id = mi.category_id
	      WHERE mi.outlet_id = ?`
	args := []any{outletID}
	if categoryID != "" && categoryID != "All" {
		q += ` AND mi.category_id = ?`
		args = append(args, categoryID)
	}
	q += ` ORDER BY mi.sort, mi.name`
	rows, err := s.DB.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := map[string]*models.MenuItem{}
	var order []string
	for rows.Next() {
		var m models.MenuItem
		var veg, best, avail int
		if err := rows.Scan(&m.ID, &m.OutletID, &m.CategoryID, &m.Category, &m.Name, &m.Description,
			&m.PricePaise, &veg, &m.ImageURL, &best, &avail, &m.Sort); err != nil {
			return nil, err
		}
		m.IsVeg = veg == 1
		m.IsBestseller = best == 1
		m.IsAvailable = avail == 1
		m.Variants = []models.ProductVariant{}
		m.ModifierGroups = []models.ModifierGroup{}
		items[m.ID] = &m
		order = append(order, m.ID)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	// Variants
	vrows, err := s.DB.QueryContext(ctx, `SELECT id, menu_item_id, name, price_paise FROM product_variants ORDER BY rowid`)
	if err != nil {
		return nil, err
	}
	defer vrows.Close()
	for vrows.Next() {
		var v models.ProductVariant
		if err := vrows.Scan(&v.ID, &v.MenuItemID, &v.Name, &v.PricePaise); err != nil {
			return nil, err
		}
		if m, ok := items[v.MenuItemID]; ok {
			v.MenuItemID = ""
			m.Variants = append(m.Variants, v)
		}
	}

	// Modifier groups + items
	grows, err := s.DB.QueryContext(ctx, `SELECT id, menu_item_id, name, is_multi_select, is_required, sort FROM modifier_groups ORDER BY sort`)
	if err != nil {
		return nil, err
	}
	defer grows.Close()
	groupOrder := map[string][]string{}
	for grows.Next() {
		var g models.ModifierGroup
		var multi, req int
		if err := grows.Scan(&g.ID, &g.MenuItemID, &g.Name, &multi, &req, &g.Sort); err != nil {
			return nil, err
		}
		g.IsMultiSelect = multi == 1
		g.IsRequired = req == 1
		g.Items = []models.ModifierItem{}
		if m, ok := items[g.MenuItemID]; ok {
			g.MenuItemID = ""
			m.ModifierGroups = append(m.ModifierGroups, g)
			groupOrder[m.ID] = append(groupOrder[m.ID], g.ID)
		}
	}

	irows, err := s.DB.QueryContext(ctx, `SELECT id, group_id, name, price_paise, sort FROM modifier_items ORDER BY sort`)
	if err != nil {
		return nil, err
	}
	defer irows.Close()
	for irows.Next() {
		var mi models.ModifierItem
		if err := irows.Scan(&mi.ID, &mi.GroupID, &mi.Name, &mi.PricePaise, &mi.Sort); err != nil {
			return nil, err
		}
		for _, m := range items {
			for gi := range m.ModifierGroups {
				if m.ModifierGroups[gi].ID == mi.GroupID {
					mi.GroupID = ""
					m.ModifierGroups[gi].Items = append(m.ModifierGroups[gi].Items, mi)
				}
			}
		}
	}

	out := make([]models.MenuItem, 0, len(order))
	for _, id := range order {
		out = append(out, *items[id])
	}
	return out, nil
}

func (s *Store) GetMenuItem(ctx context.Context, id string) (*models.MenuItem, error) {
	var outletID string
	err := s.DB.QueryRowContext(ctx, `SELECT outlet_id FROM menu_items WHERE id = ?`, id).Scan(&outletID)
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	list, err := s.ListMenu(ctx, outletID, "")
	if err != nil {
		return nil, err
	}
	for i := range list {
		if list[i].ID == id {
			return &list[i], nil
		}
	}
	return nil, httpx.ErrNotFound
}

func (s *Store) CreateMenuItem(ctx context.Context, outletID string, req models.MenuItemUpsert) (*models.MenuItem, error) {
	if req.Name == nil || *req.Name == "" || req.CategoryID == nil || *req.CategoryID == "" {
		return nil, httpx.NewError(400, "invalid_item", "name and category_id are required")
	}
	id := NewID("m")
	avail := 1
	if req.IsAvailable != nil && !*req.IsAvailable {
		avail = 0
	}
	var description, imageURL string
	if req.Description != nil {
		description = *req.Description
	}
	if req.ImageURL != nil {
		imageURL = *req.ImageURL
	}
	price := int64(0)
	if req.PricePaise != nil {
		price = *req.PricePaise
	}
	if _, err := s.DB.ExecContext(ctx,
		`INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		id, outletID, *req.CategoryID, *req.Name, description, price, b2i(req.IsVeg != nil && *req.IsVeg), imageURL, b2i(req.IsBestseller != nil && *req.IsBestseller), avail); err != nil {
		return nil, err
	}
	if err := s.upsertVariantsAndGroups(ctx, id, req); err != nil {
		return nil, err
	}
	return s.GetMenuItem(ctx, id)
}

func (s *Store) PatchMenuItem(ctx context.Context, id string, req models.MenuItemUpsert) (*models.MenuItem, error) {
	if _, err := s.GetMenuItem(ctx, id); err != nil {
		return nil, err
	}
	// Partial-patch semantics: only provided fields change. (A PATCH body with
	// just is_available used to wipe name/category — FK footgun.)
	sets := []string{}
	args := []any{}
	add := func(col string, v any) {
		sets = append(sets, col+" = ?")
		args = append(args, v)
	}
	if req.CategoryID != nil {
		add("category_id", *req.CategoryID)
	}
	if req.Name != nil {
		add("name", *req.Name)
	}
	if req.Description != nil {
		add("description", *req.Description)
	}
	if req.PricePaise != nil {
		add("price_paise", *req.PricePaise)
	}
	if req.IsVeg != nil {
		add("is_veg", b2i(*req.IsVeg))
	}
	if req.ImageURL != nil {
		add("image_url", *req.ImageURL)
	}
	if req.IsBestseller != nil {
		add("is_bestseller", b2i(*req.IsBestseller))
	}
	if req.IsAvailable != nil {
		add("is_available", b2i(*req.IsAvailable))
	}
	if len(sets) > 0 {
		args = append(args, id)
		if _, err := s.DB.ExecContext(ctx, `UPDATE menu_items SET `+strings.Join(sets, ", ")+` WHERE id = ?`, args...); err != nil {
			return nil, err
		}
	}
	// Variants/modifier groups are only rebuilt when explicitly provided;
	// otherwise the existing children are kept.
	if req.Variants != nil || req.ModifierGroups != nil {
		if _, err := s.DB.ExecContext(ctx, `DELETE FROM product_variants WHERE menu_item_id = ?`, id); err != nil {
			return nil, err
		}
		if _, err := s.DB.ExecContext(ctx, `DELETE FROM modifier_groups WHERE menu_item_id = ?`, id); err != nil {
			return nil, err
		}
		if err := s.upsertVariantsAndGroups(ctx, id, req); err != nil {
			return nil, err
		}
	}
	return s.GetMenuItem(ctx, id)
}

func (s *Store) upsertVariantsAndGroups(ctx context.Context, itemID string, req models.MenuItemUpsert) error {
	for _, v := range req.Variants {
		if _, err := s.DB.ExecContext(ctx,
			`INSERT INTO product_variants (id, menu_item_id, name, price_paise) VALUES (?, ?, ?, ?)`,
			NewID("v"), itemID, v.Name, v.PricePaise); err != nil {
			return err
		}
	}
	for gi, g := range req.ModifierGroups {
		gid := NewID("mg")
		if _, err := s.DB.ExecContext(ctx,
			`INSERT INTO modifier_groups (id, menu_item_id, name, is_multi_select, is_required, sort) VALUES (?, ?, ?, ?, ?, ?)`,
			gid, itemID, g.Name, b2i(g.IsMultiSelect), b2i(g.IsRequired), gi); err != nil {
			return err
		}
		for ii, mi := range g.Items {
			if _, err := s.DB.ExecContext(ctx,
				`INSERT INTO modifier_items (id, group_id, name, price_paise, sort) VALUES (?, ?, ?, ?, ?)`,
				NewID("mo"), gid, mi.Name, mi.PricePaise, ii); err != nil {
				return err
			}
		}
	}
	return nil
}

func (s *Store) DeleteMenuItem(ctx context.Context, id string) error {
	res, err := s.DB.ExecContext(ctx, `DELETE FROM menu_items WHERE id = ?`, id)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return httpx.ErrNotFound
	}
	return nil
}

// ---- Settings ----

func (s *Store) GetSettings(ctx context.Context, outletID string) (*models.Settings, error) {
	var st models.Settings
	var incl, auto, allow int
	err := s.DB.QueryRowContext(ctx,
		`SELECT outlet_id, restaurant_name, gst_percent, is_gst_inclusive, service_percent, packaging_paise, delivery_paise,
		        auto_print_kot, allow_reprint, billing_printer, kitchen_printer, bar_printer
		 FROM settings WHERE outlet_id = ?`, outletID).
		Scan(&st.OutletID, &st.RestaurantName, &st.GSTPercent, &incl, &st.ServicePercent, &st.PackagingPaise, &st.DeliveryPaise,
			&auto, &allow, &st.BillingPrinter, &st.KitchenPrinter, &st.BarPrinter)
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	st.IsGSTInclusive = incl == 1
	st.AutoPrintKOT = auto == 1
	st.AllowReprint = allow == 1
	return &st, nil
}

func (s *Store) PutSettings(ctx context.Context, st models.Settings) error {
	_, err := s.DB.ExecContext(ctx,
		`INSERT INTO settings (outlet_id, restaurant_name, gst_percent, is_gst_inclusive, service_percent, packaging_paise, delivery_paise,
		       auto_print_kot, allow_reprint, billing_printer, kitchen_printer, bar_printer)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		 ON CONFLICT(outlet_id) DO UPDATE SET
		   restaurant_name = excluded.restaurant_name, gst_percent = excluded.gst_percent,
		   is_gst_inclusive = excluded.is_gst_inclusive, service_percent = excluded.service_percent,
		   packaging_paise = excluded.packaging_paise, delivery_paise = excluded.delivery_paise,
		   auto_print_kot = excluded.auto_print_kot, allow_reprint = excluded.allow_reprint,
		   billing_printer = excluded.billing_printer, kitchen_printer = excluded.kitchen_printer,
		   bar_printer = excluded.bar_printer`,
		st.OutletID, st.RestaurantName, st.GSTPercent, b2i(st.IsGSTInclusive), st.ServicePercent, st.PackagingPaise, st.DeliveryPaise,
		b2i(st.AutoPrintKOT), b2i(st.AllowReprint), st.BillingPrinter, st.KitchenPrinter, st.BarPrinter)
	return err
}

func b2i(b bool) int {
	if b {
		return 1
	}
	return 0
}
