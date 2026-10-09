package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"strings"
	"time"

	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/models"
)

// ---- Outlets ----

const outletCols = `id, org_id, name, address, terminal, gstin, fssai, phone, email, timezone, is_online`

func scanOutlet(sc interface{ Scan(...any) error }) (*models.Outlet, error) {
	var o models.Outlet
	var online int
	if err := sc.Scan(&o.ID, &o.OrgID, &o.Name, &o.Address, &o.Terminal, &o.GSTIN, &o.FSSAI, &o.Phone,
		&o.Email, &o.Timezone, &online); err != nil {
		return nil, err
	}
	o.IsOnline = online == 1
	return &o, nil
}

func (s *Store) ListOutlets(ctx context.Context, orgID string) ([]models.Outlet, error) {
	rows, err := s.DB.QueryContext(ctx, `SELECT `+outletCols+` FROM outlets WHERE org_id = ? ORDER BY name`, orgID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []models.Outlet{}
	for rows.Next() {
		o, err := scanOutlet(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *o)
	}
	return out, rows.Err()
}

func (s *Store) GetOutlet(ctx context.Context, id string) (*models.Outlet, error) {
	o, err := scanOutlet(s.DB.QueryRowContext(ctx, `SELECT `+outletCols+` FROM outlets WHERE id = ?`, id))
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return o, nil
}

// OutletLocation returns the outlet's timezone (UTC when unknown/invalid),
// used for "today" and date-only report bounds.
func (s *Store) OutletLocation(ctx context.Context, outletID string) *time.Location {
	var tz string
	if err := s.DB.QueryRowContext(ctx, `SELECT timezone FROM outlets WHERE id = ?`, outletID).Scan(&tz); err == nil {
		if loc, err := time.LoadLocation(tz); err == nil {
			return loc
		}
	}
	return time.UTC
}

// PatchOutlet applies a partial outlet update (values already validated).
func (s *Store) PatchOutlet(ctx context.Context, id string, p models.OutletPatch) (*models.Outlet, error) {
	sets := []string{}
	args := []any{}
	add := func(col string, v *string) {
		if v != nil {
			sets = append(sets, col+" = ?")
			args = append(args, *v)
		}
	}
	add("name", p.Name)
	add("address", p.Address)
	add("phone", p.Phone)
	add("email", p.Email)
	add("gstin", p.GSTIN)
	add("fssai", p.FSSAI)
	add("timezone", p.Timezone)
	if len(sets) > 0 {
		args = append(args, id)
		res, err := s.DB.ExecContext(ctx, `UPDATE outlets SET `+strings.Join(sets, ", ")+` WHERE id = ?`, args...)
		if err != nil {
			return nil, err
		}
		if n, _ := res.RowsAffected(); n == 0 {
			return nil, httpx.ErrNotFound
		}
	}
	return s.GetOutlet(ctx, id)
}

func (s *Store) CountOutlets(ctx context.Context, orgID string) (int, error) {
	var n int
	err := s.DB.QueryRowContext(ctx, `SELECT COUNT(*) FROM outlets WHERE org_id = ?`, orgID).Scan(&n)
	return n, err
}

// CreateOutlet provisions a new outlet under an org (SaaS onboarding).
func (s *Store) CreateOutlet(ctx context.Context, orgID string, o models.Outlet) (*models.Outlet, error) {
	id := NewID("out")
	online := 1
	if !o.IsOnline {
		online = 0
	}
	tz := o.Timezone
	if tz == "" {
		tz = "Asia/Kolkata"
	}
	_, err := s.DB.ExecContext(ctx,
		`INSERT INTO outlets (id, org_id, name, address, terminal, gstin, fssai, phone, email, timezone, is_online)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		id, orgID, o.Name, o.Address, o.Terminal, o.GSTIN, o.FSSAI, o.Phone, o.Email, tz, online)
	if err != nil {
		return nil, err
	}
	defaultCats := []string{"Starters", "Soups", "Main Course", "Biryani", "Chinese", "Pizza", "Drinks", "Desserts"}
	for i, c := range defaultCats {
		_, _ = s.DB.ExecContext(ctx,
			`INSERT INTO menu_categories (id, outlet_id, name, sort) VALUES (?, ?, ?, ?) ON CONFLICT DO NOTHING`,
			NewID("cat"), id, c, i)
	}
	return s.GetOutlet(ctx, id)
}

// ---- Staff ----

type StaffRow struct {
	models.Staff
	PINHash string
}

// ListStaff lists active staff of an org. When outletID is non-empty only that
// outlet's staff (plus org-wide staff with outlet_id NULL) are returned.
func (s *Store) ListStaff(ctx context.Context, orgID, outletID string) ([]models.Staff, error) {
	q := `SELECT id, org_id, outlet_id, name, role, avatar_url, mobile, is_active, COALESCE(is_protected, 0) FROM staff WHERE org_id = ? AND is_active = 1`
	args := []any{orgID}
	if outletID != "" {
		q += ` AND (outlet_id = ? OR (outlet_id IS NULL AND role != 'waiter'))`
		args = append(args, outletID)
	}
	q += ` ORDER BY name`
	rows, err := s.DB.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []models.Staff
	for rows.Next() {
		st, err := scanStaff(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *st)
	}
	return out, rows.Err()
}

func scanStaff(sc interface{ Scan(...any) error }) (*models.Staff, error) {
	var st models.Staff
	var outlet sql.NullString
	var active int
	var prot int
	if err := sc.Scan(&st.ID, &st.OrgID, &outlet, &st.Name, &st.Role, &st.AvatarURL, &st.Mobile, &active, &prot); err != nil {
		return nil, err
	}
	st.IsActive = active == 1
	st.IsProtected = prot == 1
	if outlet.Valid {
		st.OutletID = &outlet.String
	}
	return &st, nil
}

func (s *Store) GetStaff(ctx context.Context, id string) (*StaffRow, error) {
	var st StaffRow
	var outlet sql.NullString
	var active int
	var prot int
	err := s.DB.QueryRowContext(ctx,
		`SELECT id, org_id, outlet_id, name, role, avatar_url, mobile, is_active, COALESCE(is_protected, 0), pin_hash FROM staff WHERE id = ?`, id).
		Scan(&st.ID, &st.OrgID, &outlet, &st.Name, &st.Role, &st.AvatarURL, &st.Mobile, &active, &prot, &st.PINHash)
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	st.IsActive = active == 1
	st.IsProtected = prot == 1
	if outlet.Valid {
		st.OutletID = &outlet.String
	}
	return &st, nil
}

func (s *Store) CreateStaff(ctx context.Context, orgID string, st models.StaffCreate, pinHash string) (*models.Staff, error) {
	id := NewID("st")
	outlet := any(nil)
	if st.OutletID != nil && *st.OutletID != "" {
		outlet = *st.OutletID
	}
	_, err := s.DB.ExecContext(ctx,
		`INSERT INTO staff (id, org_id, outlet_id, name, role, pin_hash, avatar_url, mobile, is_active, is_protected)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 0)`,
		id, orgID, outlet, st.Name, st.Role, pinHash, st.AvatarURL, st.Mobile)
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
	if p.Floor != nil && strings.TrimSpace(*p.Floor) != "" {
		if _, err := s.DB.ExecContext(ctx, `UPDATE tables SET floor = ? WHERE id = ?`, *p.Floor, id); err != nil {
			return nil, err
		}
	}
	_ = t
	return s.GetTable(ctx, id)
}

// ---- Settings ----

func (s *Store) GetSettings(ctx context.Context, outletID string) (*models.Settings, error) {
	var st models.Settings
	var incl, auto, allow int
	var sectionsTxt string
	err := s.DB.QueryRowContext(ctx,
		`SELECT outlet_id, restaurant_name, gst_percent, is_gst_inclusive, service_percent, packaging_paise, delivery_paise,
		        auto_print_kot, allow_reprint, billing_printer, kitchen_printer, bar_printer, sections,
		        upi_id, upi_name, upi_qr_image
		 FROM settings WHERE outlet_id = ?`, outletID).
		Scan(&st.OutletID, &st.RestaurantName, &st.GSTPercent, &incl, &st.ServicePercent, &st.PackagingPaise, &st.DeliveryPaise,
			&auto, &allow, &st.BillingPrinter, &st.KitchenPrinter, &st.BarPrinter, &sectionsTxt,
			&st.UPIID, &st.UPIName, &st.UPIQrImage)
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	st.IsGSTInclusive = incl == 1
	st.AutoPrintKOT = auto == 1
	st.AllowReprint = allow == 1
	if sectionsTxt != "" {
		_ = json.Unmarshal([]byte(sectionsTxt), &st.Sections)
	}
	return &st, nil
}

func (s *Store) PutSettings(ctx context.Context, st models.Settings) error {
	_, err := s.DB.ExecContext(ctx,
		`INSERT INTO settings (outlet_id, restaurant_name, gst_percent, is_gst_inclusive, service_percent, packaging_paise, delivery_paise,
		       auto_print_kot, allow_reprint, billing_printer, kitchen_printer, bar_printer, sections,
		       upi_id, upi_name, upi_qr_image)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		 ON CONFLICT(outlet_id) DO UPDATE SET
		   restaurant_name = excluded.restaurant_name, gst_percent = excluded.gst_percent,
		   is_gst_inclusive = excluded.is_gst_inclusive, service_percent = excluded.service_percent,
		   packaging_paise = excluded.packaging_paise, delivery_paise = excluded.delivery_paise,
		   auto_print_kot = excluded.auto_print_kot, allow_reprint = excluded.allow_reprint,
		   billing_printer = excluded.billing_printer, kitchen_printer = excluded.kitchen_printer,
		   bar_printer = excluded.bar_printer, sections = excluded.sections,
		   upi_id = excluded.upi_id, upi_name = excluded.upi_name, upi_qr_image = excluded.upi_qr_image`,
		st.OutletID, st.RestaurantName, st.GSTPercent, b2i(st.IsGSTInclusive), st.ServicePercent, st.PackagingPaise, st.DeliveryPaise,
		b2i(st.AutoPrintKOT), b2i(st.AllowReprint), st.BillingPrinter, st.KitchenPrinter, st.BarPrinter, sectionsJSON(st.Sections),
		st.UPIID, st.UPIName, st.UPIQrImage)
	return err
}

// sectionsJSON encodes a section list for the TEXT column ('[]' when nil).
func sectionsJSON(s []string) string {
	if s == nil {
		s = []string{}
	}
	b, _ := json.Marshal(s)
	return string(b)
}

func b2i(b bool) int {
	if b {
		return 1
	}
	return 0
}
