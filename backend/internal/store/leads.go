package store

// Landing lead capture (migration 009).

import (
	"context"

	"foodpos/backend/internal/models"
)

func (s *Store) CreateLead(ctx context.Context, l *models.Lead) error {
	_, err := s.DB.ExecContext(ctx,
		`INSERT INTO leads (id, restaurant_name, contact_name, phone, city, outlet_format, plan_interest, source, status, created_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		l.ID, l.RestaurantName, l.ContactName, l.Phone, l.City,
		l.OutletFormat, l.PlanInterest, l.Source, l.Status, l.CreatedAt)
	return err
}

func (s *Store) ListLeads(ctx context.Context, limit int) ([]models.Lead, error) {
	rows, err := s.DB.QueryContext(ctx,
		`SELECT id, restaurant_name, contact_name, phone, city, outlet_format, plan_interest, source, status, created_at
		 FROM leads ORDER BY created_at DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []models.Lead
	for rows.Next() {
		var l models.Lead
		if err := rows.Scan(&l.ID, &l.RestaurantName, &l.ContactName, &l.Phone, &l.City,
			&l.OutletFormat, &l.PlanInterest, &l.Source, &l.Status, &l.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, l)
	}
	return out, rows.Err()
}
