package store

// Operator-only operations used by cmd/admin (menu import, moving an outlet
// between organizations). Not exposed over HTTP.

import (
	"context"
	"database/sql"
	"fmt"
	"strings"

	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/menuimport"
	"foodpos/backend/internal/models"
)

type ImportResult struct {
	Created, Updated, Restored int
	Removed                    int64
}

// ImportMenu upserts parsed menu rows into an outlet, matching existing items
// by case-insensitive name (ids — and therefore order history — are kept;
// soft-deleted matches are revived). Category order follows the file. With
// replace, live items not in the file are soft-deleted.
func (s *Store) ImportMenu(ctx context.Context, outletID string, items []menuimport.Item, replace bool) (ImportResult, error) {
	var res ImportResult
	if _, err := s.GetOutlet(ctx, outletID); err != nil {
		return res, fmt.Errorf("outlet %s: %w", outletID, err)
	}
	catIDs := map[string]string{}
	for i, name := range menuimport.Categories(items) {
		id, err := s.CategoryID(ctx, outletID, name)
		if err != nil {
			return res, fmt.Errorf("category %q: %w", name, err)
		}
		if err := s.SetCategorySort(ctx, id, i); err != nil {
			return res, err
		}
		catIDs[name] = id
	}
	keep := make([]string, 0, len(items))
	for _, it := range items {
		catID := catIDs[it.Category]
		name, desc, price := it.Name, it.Description, it.PricePaise
		veg, best, avail := it.IsVeg, it.Bestseller, true
		up := models.MenuItemUpsert{
			CategoryID: &catID, Name: &name, Description: &desc, PricePaise: &price,
			IsVeg: &veg, IsBestseller: &best, IsAvailable: &avail,
			Variants: []models.ProductVariant{},
		}
		id, deleted, err := s.FindMenuItemByName(ctx, outletID, it.Name)
		switch {
		case err == nil:
			if deleted {
				if err := s.RestoreMenuItem(ctx, id); err != nil {
					return res, err
				}
				res.Restored++
			}
			existing, err := s.GetMenuItem(ctx, id)
			if err != nil {
				return res, err
			}
			byName := map[string]string{}
			for _, v := range existing.Variants {
				byName[strings.ToLower(v.Name)] = v.ID
			}
			for _, v := range it.Variants() {
				up.Variants = append(up.Variants, models.ProductVariant{ID: byName[strings.ToLower(v.Name)], Name: v.Name, PricePaise: v.PricePaise})
			}
			if _, err := s.PatchMenuItem(ctx, id, up); err != nil {
				return res, fmt.Errorf("update %q: %w", it.Name, err)
			}
			res.Updated++
			keep = append(keep, id)
		case err == httpx.ErrNotFound:
			for _, v := range it.Variants() {
				up.Variants = append(up.Variants, models.ProductVariant{Name: v.Name, PricePaise: v.PricePaise})
			}
			m, err := s.CreateMenuItem(ctx, outletID, up)
			if err != nil {
				return res, fmt.Errorf("create %q: %w", it.Name, err)
			}
			res.Created++
			keep = append(keep, m.ID)
		default:
			return res, err
		}
	}
	if replace {
		n, err := s.SoftDeleteMenuItemsExcept(ctx, outletID, keep)
		if err != nil {
			return res, err
		}
		res.Removed = n
	}
	return res, nil
}

// MoveOutlet re-homes an outlet (and everything bound to it) into another
// organization: the outlet row, its outlet-bound staff, attendance and push
// tokens. Org-wide staff of the old org stay behind. Open refresh sessions
// on the outlet are revoked so terminals must sign in again under the new org.
func (s *Store) MoveOutlet(ctx context.Context, outletID, toOrgID string) error {
	if _, err := s.GetOrganization(ctx, toOrgID); err != nil {
		return fmt.Errorf("target org %s: %w", toOrgID, err)
	}
	return s.withTx(ctx, func(tx *sql.Tx) error {
		res, err := tx.ExecContext(ctx, `UPDATE outlets SET org_id = ? WHERE id = ?`, toOrgID, outletID)
		if err != nil {
			return err
		}
		if n, _ := res.RowsAffected(); n == 0 {
			return fmt.Errorf("outlet %s: %w", outletID, httpx.ErrNotFound)
		}
		for _, q := range []string{
			`UPDATE staff SET org_id = ? WHERE outlet_id = ?`,
			`UPDATE staff_attendance SET org_id = ? WHERE outlet_id = ?`,
			`UPDATE device_tokens SET org_id = ? WHERE outlet_id = ?`,
		} {
			if _, err := tx.ExecContext(ctx, q, toOrgID, outletID); err != nil {
				return err
			}
		}
		_, err = tx.ExecContext(ctx, `UPDATE auth_refresh SET revoked_at = ? WHERE outlet_id = ? AND revoked_at IS NULL`,
			TimeStr(Now()), outletID)
		return err
	})
}
