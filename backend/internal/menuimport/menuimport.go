// Package menuimport parses a restaurant menu CSV (the format of
// assets/green_candle_menu.csv) into menu rows ready for upsert. It is pure
// (no database) so the format is unit-tested on its own.
//
// Format: UTF-8 (BOM allowed), header
//
//	Category,Item (Marathi),Item English Transliteration,Half Price (₹),Full Price (₹),Variants,Bestseller,Veg,Description
//
// The English transliteration is the item name (the Marathi name goes in
// front of the description so it still prints on the menu). Prices are
// rupees. With a Half price the item gets variants Half/Full and its base
// price is the Full price; without one it is a single-price item.
package menuimport

import (
	"encoding/csv"
	"fmt"
	"io"
	"math"
	"strconv"
	"strings"
)

// Item is one parsed menu row. Prices are paise.
type Item struct {
	Category    string
	Name        string
	LocalName   string
	Description string
	PricePaise  int64
	HalfPaise   int64 // 0 = no Half/Full variants
	IsVeg       bool
	Bestseller  bool
}

// Variants returns the Half/Full variant pair (empty for single-price items).
func (it Item) Variants() []Variant {
	if it.HalfPaise <= 0 {
		return nil
	}
	return []Variant{{Name: "Half", PricePaise: it.HalfPaise}, {Name: "Full", PricePaise: it.PricePaise}}
}

type Variant struct {
	Name       string
	PricePaise int64
}

var header = []string{"category", "item (marathi)", "item english transliteration",
	"half price (₹)", "full price (₹)", "variants", "bestseller", "veg", "description"}

// Parse reads the CSV. Rows with errors abort the import (with the line
// number) so a half-imported menu never reaches a live outlet. Duplicate
// names (case-insensitive) are rejected for the same reason.
func Parse(r io.Reader) ([]Item, error) {
	cr := csv.NewReader(r)
	cr.FieldsPerRecord = -1
	cr.TrimLeadingSpace = true
	rows, err := cr.ReadAll()
	if err != nil {
		return nil, fmt.Errorf("read csv: %w", err)
	}
	if len(rows) == 0 {
		return nil, fmt.Errorf("empty file")
	}
	head := rows[0]
	if len(head) > 0 {
		head[0] = strings.TrimPrefix(head[0], string(rune(0xFEFF))) // UTF-8 BOM
	}
	if len(head) < len(header) {
		return nil, fmt.Errorf("header has %d columns, want %d", len(head), len(header))
	}
	for i, want := range header {
		if got := strings.ToLower(strings.TrimSpace(head[i])); got != want {
			return nil, fmt.Errorf("header column %d is %q, want %q", i+1, head[i], want)
		}
	}
	var out []Item
	seen := map[string]int{}
	for i, row := range rows[1:] {
		line := i + 2
		if blank(row) {
			continue
		}
		for len(row) < len(header) {
			row = append(row, "")
		}
		it := Item{
			Category:    strings.TrimSpace(row[0]),
			LocalName:   strings.TrimSpace(row[1]),
			Name:        strings.TrimSpace(row[2]),
			Description: strings.TrimSpace(row[8]),
			Bestseller:  truthy(row[6]),
			IsVeg:       !strings.Contains(strings.ToUpper(row[7]), "NON"),
		}
		if it.Category == "" || it.Name == "" {
			return nil, fmt.Errorf("line %d: category and English name are required", line)
		}
		key := strings.ToLower(it.Name)
		if prev, dup := seen[key]; dup {
			return nil, fmt.Errorf("line %d: duplicate item %q (first on line %d)", line, it.Name, prev)
		}
		seen[key] = line
		half, err := rupees(row[3])
		if err != nil {
			return nil, fmt.Errorf("line %d: half price: %w", line, err)
		}
		full, err := rupees(row[4])
		if err != nil {
			return nil, fmt.Errorf("line %d: full price: %w", line, err)
		}
		if full <= 0 {
			if half <= 0 {
				return nil, fmt.Errorf("line %d: %q has no price", line, it.Name)
			}
			full, half = half, 0 // only one price given
		}
		it.PricePaise, it.HalfPaise = full, half
		if it.LocalName != "" && it.LocalName != it.Name {
			if it.Description == "" {
				it.Description = it.LocalName
			} else {
				it.Description = it.LocalName + " — " + it.Description
			}
		}
		out = append(out, it)
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("no menu rows")
	}
	return out, nil
}

// Categories returns the distinct categories in first-appearance order (the
// menu's display order).
func Categories(items []Item) []string {
	var out []string
	seen := map[string]bool{}
	for _, it := range items {
		if !seen[it.Category] {
			seen[it.Category] = true
			out = append(out, it.Category)
		}
	}
	return out
}

func blank(row []string) bool {
	for _, c := range row {
		if strings.TrimSpace(c) != "" {
			return false
		}
	}
	return true
}

func truthy(v string) bool {
	switch strings.ToUpper(strings.TrimSpace(v)) {
	case "YES", "Y", "TRUE", "1", "★", "BESTSELLER":
		return true
	}
	return false
}

// rupees parses "₹1,250.50" style amounts into paise ("" = 0).
func rupees(v string) (int64, error) {
	v = strings.NewReplacer("₹", "", ",", "", "Rs.", "", "Rs", "").Replace(strings.TrimSpace(v))
	v = strings.TrimSpace(v)
	if v == "" {
		return 0, nil
	}
	f, err := strconv.ParseFloat(v, 64)
	if err != nil || f < 0 || math.IsInf(f, 0) || math.IsNaN(f) {
		return 0, fmt.Errorf("invalid amount %q", v)
	}
	return int64(math.Round(f * 100)), nil
}
