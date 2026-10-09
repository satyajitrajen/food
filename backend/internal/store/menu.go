package store

// Menu catalog: items, variants, modifier groups/items and categories.
// Reads are scoped (children are loaded only for the requested items — never
// whole tables); writes run in one transaction and keep child ids stable so
// order lines that reference a variant/modifier id stay resolvable. Deleting
// an item is a soft delete: sold items stay referenced by order_items.

import (
	"context"
	"database/sql"
	"strings"

	"github.com/lib/pq"

	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/models"
)

const menuItemCols = `mi.id, mi.outlet_id, mi.category_id, COALESCE(mc.name,''), mi.name, mi.description, mi.price_paise,
	mi.is_veg, mi.image_url, mi.is_bestseller, mi.is_available, mi.sort, mi.is_deleted`

func scanMenuItem(sc interface{ Scan(...any) error }) (*models.MenuItem, error) {
	var m models.MenuItem
	var veg, best, avail, deleted int
	if err := sc.Scan(&m.ID, &m.OutletID, &m.CategoryID, &m.Category, &m.Name, &m.Description,
		&m.PricePaise, &veg, &m.ImageURL, &best, &avail, &m.Sort, &deleted); err != nil {
		return nil, err
	}
	m.IsVeg = veg == 1
	m.IsBestseller = best == 1
	m.IsAvailable = avail == 1
	m.IsDeleted = deleted == 1
	m.Variants = []models.ProductVariant{}
	m.ModifierGroups = []models.ModifierGroup{}
	return &m, nil
}

// ListMenu returns the outlet's live (not deleted) menu.
func (s *Store) ListMenu(ctx context.Context, outletID, categoryID string) ([]models.MenuItem, error) {
	q := `SELECT ` + menuItemCols + `
	      FROM menu_items mi LEFT JOIN menu_categories mc ON mc.id = mi.category_id
	      WHERE mi.outlet_id = ? AND mi.is_deleted = 0`
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
	out := []models.MenuItem{}
	for rows.Next() {
		m, err := scanMenuItem(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *m)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	rows.Close()
	if err := loadMenuChildren(ctx, s.DB, out); err != nil {
		return nil, err
	}
	return out, nil
}

// GetMenuItem loads one item (deleted ones included — callers decide) with
// its variants and modifier groups.
func (s *Store) GetMenuItem(ctx context.Context, id string) (*models.MenuItem, error) {
	return getMenuItemQ(ctx, s.DB, id)
}

func getMenuItemQ(ctx context.Context, q Querier, id string) (*models.MenuItem, error) {
	m, err := scanMenuItem(q.QueryRowContext(ctx, `SELECT `+menuItemCols+`
		FROM menu_items mi LEFT JOIN menu_categories mc ON mc.id = mi.category_id WHERE mi.id = ?`, id))
	if err == sql.ErrNoRows {
		return nil, httpx.ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	list := []models.MenuItem{*m}
	if err := loadMenuChildren(ctx, q, list); err != nil {
		return nil, err
	}
	return &list[0], nil
}

// loadMenuChildren attaches variants, modifier groups and modifier items to
// items in three queries scoped to those items.
func loadMenuChildren(ctx context.Context, q Querier, items []models.MenuItem) error {
	if len(items) == 0 {
		return nil
	}
	pos := make(map[string]int, len(items))
	ids := make([]string, len(items))
	for i := range items {
		pos[items[i].ID] = i
		ids[i] = items[i].ID
	}
	vrows, err := q.QueryContext(ctx, `SELECT id, menu_item_id, name, price_paise FROM product_variants
		WHERE menu_item_id = ANY(?) ORDER BY seq`, pq.Array(ids))
	if err != nil {
		return err
	}
	for vrows.Next() {
		var v models.ProductVariant
		if err := vrows.Scan(&v.ID, &v.MenuItemID, &v.Name, &v.PricePaise); err != nil {
			vrows.Close()
			return err
		}
		if i, ok := pos[v.MenuItemID]; ok {
			v.MenuItemID = ""
			items[i].Variants = append(items[i].Variants, v)
		}
	}
	vrows.Close()
	if err := vrows.Err(); err != nil {
		return err
	}

	grows, err := q.QueryContext(ctx, `SELECT id, menu_item_id, name, is_multi_select, is_required, sort FROM modifier_groups
		WHERE menu_item_id = ANY(?) ORDER BY sort, id`, pq.Array(ids))
	if err != nil {
		return err
	}
	type gref struct{ item, group int }
	groupPos := map[string]gref{}
	var groupIDs []string
	for grows.Next() {
		var g models.ModifierGroup
		var multi, req int
		var itemID string
		if err := grows.Scan(&g.ID, &itemID, &g.Name, &multi, &req, &g.Sort); err != nil {
			grows.Close()
			return err
		}
		g.IsMultiSelect = multi == 1
		g.IsRequired = req == 1
		g.Items = []models.ModifierItem{}
		if i, ok := pos[itemID]; ok {
			items[i].ModifierGroups = append(items[i].ModifierGroups, g)
			groupPos[g.ID] = gref{i, len(items[i].ModifierGroups) - 1}
			groupIDs = append(groupIDs, g.ID)
		}
	}
	grows.Close()
	if err := grows.Err(); err != nil {
		return err
	}
	if len(groupIDs) == 0 {
		return nil
	}
	irows, err := q.QueryContext(ctx, `SELECT id, group_id, name, price_paise, sort FROM modifier_items
		WHERE group_id = ANY(?) ORDER BY sort, id`, pq.Array(groupIDs))
	if err != nil {
		return err
	}
	defer irows.Close()
	for irows.Next() {
		var mi models.ModifierItem
		if err := irows.Scan(&mi.ID, &mi.GroupID, &mi.Name, &mi.PricePaise, &mi.Sort); err != nil {
			return err
		}
		if ref, ok := groupPos[mi.GroupID]; ok {
			mi.GroupID = ""
			g := &items[ref.item].ModifierGroups[ref.group]
			g.Items = append(g.Items, mi)
		}
	}
	return irows.Err()
}

// CategoryID resolves a category reference for an outlet: menu admin clients
// send the display *name* (the Flutter UI only knows names), while order code
// may send the real id. Accepts either; an unknown non-empty name creates the
// category.
func (s *Store) CategoryID(ctx context.Context, outletID, nameOrID string) (string, error) {
	var id string
	err := s.DB.QueryRowContext(ctx,
		`SELECT id FROM menu_categories WHERE outlet_id = ? AND (id = ? OR name = ?) LIMIT 1`,
		outletID, nameOrID, nameOrID).Scan(&id)
	if err == nil {
		return id, nil
	}
	if err == sql.ErrNoRows {
		trimmed := strings.TrimSpace(nameOrID)
		if trimmed != "" {
			newID := NewID("cat")
			if _, insErr := s.DB.ExecContext(ctx,
				`INSERT INTO menu_categories (id, outlet_id, name, sort) VALUES (?, ?, ?, 0)`,
				newID, outletID, trimmed); insErr == nil {
				return newID, nil
			}
		}
		return "", httpx.NewError(400, "invalid_category", "Unknown category")
	}
	return "", err
}

// SetCategorySort sets a category's display position (menu import).
func (s *Store) SetCategorySort(ctx context.Context, categoryID string, sort int) error {
	_, err := s.DB.ExecContext(ctx, `UPDATE menu_categories SET sort = ? WHERE id = ?`, sort, categoryID)
	return err
}

func validateMenuPrices(req models.MenuItemUpsert) error {
	bad := httpx.NewError(400, "invalid_price", "Prices cannot be negative")
	if req.PricePaise != nil && *req.PricePaise < 0 {
		return bad
	}
	for _, v := range req.Variants {
		if v.PricePaise < 0 {
			return bad
		}
	}
	for _, g := range req.ModifierGroups {
		for _, mi := range g.Items {
			if mi.PricePaise < 0 {
				return bad
			}
		}
	}
	return nil
}

func (s *Store) CreateMenuItem(ctx context.Context, outletID string, req models.MenuItemUpsert) (*models.MenuItem, error) {
	if req.Name == nil || strings.TrimSpace(*req.Name) == "" || req.CategoryID == nil || *req.CategoryID == "" {
		return nil, httpx.NewError(400, "invalid_item", "name and category_id are required")
	}
	if err := validateMenuPrices(req); err != nil {
		return nil, err
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
	var out *models.MenuItem
	err := s.withTx(ctx, func(tx *sql.Tx) error {
		if _, err := tx.ExecContext(ctx,
			`INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available)
			 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			id, outletID, *req.CategoryID, strings.TrimSpace(*req.Name), description, price, b2i(req.IsVeg != nil && *req.IsVeg),
			imageURL, b2i(req.IsBestseller != nil && *req.IsBestseller), avail); err != nil {
			return err
		}
		if err := syncVariants(ctx, tx, id, req.Variants); err != nil {
			return err
		}
		if err := syncModifierGroups(ctx, tx, id, req.ModifierGroups); err != nil {
			return err
		}
		var err error
		out, err = getMenuItemQ(ctx, tx, id)
		return err
	})
	return out, err
}

// PatchMenuItem applies a partial update. Variants / modifier groups are
// synced only when present in the body: children are matched by id (kept,
// updated in place), new ones inserted, and only the ones missing from the
// body deleted — ids stay stable across edits.
func (s *Store) PatchMenuItem(ctx context.Context, id string, req models.MenuItemUpsert) (*models.MenuItem, error) {
	if err := validateMenuPrices(req); err != nil {
		return nil, err
	}
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
		name := strings.TrimSpace(*req.Name)
		if name == "" {
			return nil, httpx.NewError(400, "invalid_item", "name cannot be empty")
		}
		add("name", name)
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
	var out *models.MenuItem
	err := s.withTx(ctx, func(tx *sql.Tx) error {
		var exists int
		if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM menu_items WHERE id = ? AND is_deleted = 0`, id).Scan(&exists); err != nil {
			return err
		}
		if exists == 0 {
			return httpx.ErrNotFound
		}
		if len(sets) > 0 {
			a := append(append([]any{}, args...), id)
			if _, err := tx.ExecContext(ctx, `UPDATE menu_items SET `+strings.Join(sets, ", ")+` WHERE id = ?`, a...); err != nil {
				return err
			}
		}
		if req.Variants != nil {
			if err := syncVariants(ctx, tx, id, req.Variants); err != nil {
				return err
			}
		}
		if req.ModifierGroups != nil {
			if err := syncModifierGroups(ctx, tx, id, req.ModifierGroups); err != nil {
				return err
			}
		}
		var err error
		out, err = getMenuItemQ(ctx, tx, id)
		return err
	})
	return out, err
}

// childIDs returns the ids of rows in table whose parentCol = parentID.
func childIDs(ctx context.Context, tx *sql.Tx, table, parentCol, parentID string) (map[string]bool, error) {
	rows, err := tx.QueryContext(ctx, `SELECT id FROM `+table+` WHERE `+parentCol+` = ?`, parentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]bool{}
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out[id] = true
	}
	return out, rows.Err()
}

// deleteExcept removes children of parentID not in keep.
func deleteExcept(ctx context.Context, tx *sql.Tx, table, parentCol, parentID string, existing, keep map[string]bool) error {
	for id := range existing {
		if keep[id] {
			continue
		}
		if _, err := tx.ExecContext(ctx, `DELETE FROM `+table+` WHERE id = ? AND `+parentCol+` = ?`, id, parentID); err != nil {
			return err
		}
	}
	return nil
}

func syncVariants(ctx context.Context, tx *sql.Tx, itemID string, variants []models.ProductVariant) error {
	existing, err := childIDs(ctx, tx, "product_variants", "menu_item_id", itemID)
	if err != nil {
		return err
	}
	keep := map[string]bool{}
	for _, v := range variants {
		name := strings.TrimSpace(v.Name)
		if existing[v.ID] {
			if _, err := tx.ExecContext(ctx, `UPDATE product_variants SET name = ?, price_paise = ? WHERE id = ?`,
				name, v.PricePaise, v.ID); err != nil {
				return err
			}
			keep[v.ID] = true
			continue
		}
		// Unknown/local ids (e.g. offline "v1") get a server id.
		if _, err := tx.ExecContext(ctx, `INSERT INTO product_variants (id, menu_item_id, name, price_paise) VALUES (?, ?, ?, ?)`,
			NewID("v"), itemID, name, v.PricePaise); err != nil {
			return err
		}
	}
	return deleteExcept(ctx, tx, "product_variants", "menu_item_id", itemID, existing, keep)
}

func syncModifierGroups(ctx context.Context, tx *sql.Tx, itemID string, groups []models.ModifierGroup) error {
	existing, err := childIDs(ctx, tx, "modifier_groups", "menu_item_id", itemID)
	if err != nil {
		return err
	}
	keep := map[string]bool{}
	for gi, g := range groups {
		gid := g.ID
		if existing[gid] {
			if _, err := tx.ExecContext(ctx, `UPDATE modifier_groups SET name = ?, is_multi_select = ?, is_required = ?, sort = ? WHERE id = ?`,
				g.Name, b2i(g.IsMultiSelect), b2i(g.IsRequired), gi, gid); err != nil {
				return err
			}
			keep[gid] = true
		} else {
			gid = NewID("mg")
			if _, err := tx.ExecContext(ctx,
				`INSERT INTO modifier_groups (id, menu_item_id, name, is_multi_select, is_required, sort) VALUES (?, ?, ?, ?, ?, ?)`,
				gid, itemID, g.Name, b2i(g.IsMultiSelect), b2i(g.IsRequired), gi); err != nil {
				return err
			}
		}
		existingItems, err := childIDs(ctx, tx, "modifier_items", "group_id", gid)
		if err != nil {
			return err
		}
		keepItems := map[string]bool{}
		for ii, mi := range g.Items {
			if existingItems[mi.ID] {
				if _, err := tx.ExecContext(ctx, `UPDATE modifier_items SET name = ?, price_paise = ?, sort = ? WHERE id = ?`,
					mi.Name, mi.PricePaise, ii, mi.ID); err != nil {
					return err
				}
				keepItems[mi.ID] = true
				continue
			}
			if _, err := tx.ExecContext(ctx,
				`INSERT INTO modifier_items (id, group_id, name, price_paise, sort) VALUES (?, ?, ?, ?, ?)`,
				NewID("mo"), gid, mi.Name, mi.PricePaise, ii); err != nil {
				return err
			}
		}
		if err := deleteExcept(ctx, tx, "modifier_items", "group_id", gid, existingItems, keepItems); err != nil {
			return err
		}
	}
	return deleteExcept(ctx, tx, "modifier_groups", "menu_item_id", itemID, existing, keep)
}

// DeleteMenuItem soft-deletes: the row stays for order_items' FK and bill
// history, but disappears from menus and can no longer be ordered.
func (s *Store) DeleteMenuItem(ctx context.Context, id string) error {
	res, err := s.DB.ExecContext(ctx, `UPDATE menu_items SET is_deleted = 1, is_available = 0 WHERE id = ? AND is_deleted = 0`, id)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return httpx.ErrNotFound
	}
	return nil
}

// FindMenuItemByName resolves an outlet's item by case-insensitive name
// (deleted rows included so an import can revive them).
func (s *Store) FindMenuItemByName(ctx context.Context, outletID, name string) (id string, deleted bool, err error) {
	var del int
	err = s.DB.QueryRowContext(ctx, `SELECT id, is_deleted FROM menu_items WHERE outlet_id = ? AND lower(name) = lower(?)
		ORDER BY is_deleted, id LIMIT 1`, outletID, strings.TrimSpace(name)).Scan(&id, &del)
	if err == sql.ErrNoRows {
		return "", false, httpx.ErrNotFound
	}
	return id, del == 1, err
}

// RestoreMenuItem undoes a soft delete.
func (s *Store) RestoreMenuItem(ctx context.Context, id string) error {
	_, err := s.DB.ExecContext(ctx, `UPDATE menu_items SET is_deleted = 0 WHERE id = ?`, id)
	return err
}

// SoftDeleteMenuItemsExcept soft-deletes every live item of the outlet not in
// keep (menu import --replace). Returns how many were removed.
func (s *Store) SoftDeleteMenuItemsExcept(ctx context.Context, outletID string, keep []string) (int64, error) {
	res, err := s.DB.ExecContext(ctx, `UPDATE menu_items SET is_deleted = 1, is_available = 0
		WHERE outlet_id = ? AND is_deleted = 0 AND NOT (id = ANY(?))`, outletID, pq.Array(keep))
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}
