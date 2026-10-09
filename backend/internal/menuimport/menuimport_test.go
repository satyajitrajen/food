package menuimport

import (
	"os"
	"strings"
	"testing"
)

func TestParseSample(t *testing.T) {
	f, err := os.Open("testdata/menu_sample.csv")
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	items, err := Parse(f)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if len(items) != 6 {
		t.Fatalf("got %d items, want 6 (blank row skipped)", len(items))
	}

	first := items[0]
	if first.Name != "Special Arakha Masoor" || first.Category != "अरख्खा मसूर स्पेशल" {
		t.Fatalf("first row = %+v", first)
	}
	// Half present → Half/Full variants, base = Full.
	if first.PricePaise != 10000 || first.HalfPaise != 6000 {
		t.Fatalf("prices = %d/%d, want 10000/6000", first.PricePaise, first.HalfPaise)
	}
	v := first.Variants()
	if len(v) != 2 || v[0].Name != "Half" || v[0].PricePaise != 6000 || v[1].Name != "Full" || v[1].PricePaise != 10000 {
		t.Fatalf("variants = %+v", v)
	}
	if !strings.HasPrefix(first.Description, "स्पेशल अरख्खा मसूर — ") {
		t.Fatalf("local name should lead the description: %q", first.Description)
	}
	if !first.IsVeg || first.Bestseller {
		t.Fatalf("flags = veg %v best %v", first.IsVeg, first.Bestseller)
	}

	single := items[3]
	if single.Name != "Paneer Masala" || single.PricePaise != 18000 || single.Variants() != nil {
		t.Fatalf("single-price row = %+v", single)
	}
	if !items[4].Bestseller {
		t.Fatal("YES bestseller not parsed")
	}
	nonveg := items[5]
	if nonveg.IsVeg || !nonveg.Bestseller || nonveg.PricePaise != 125050 {
		t.Fatalf("non-veg row = %+v", nonveg)
	}

	cats := Categories(items)
	if len(cats) != 4 || cats[0] != "अरख्खा मसूर स्पेशल" || cats[3] != "Starters" {
		t.Fatalf("categories = %v", cats)
	}
}

func TestParseRejectsBadInput(t *testing.T) {
	const head = "Category,Item (Marathi),Item English Transliteration,Half Price (₹),Full Price (₹),Variants,Bestseller,Veg,Description\n"
	cases := map[string]string{
		"bad header":   "Name,Price\nA,1\n",
		"no price":     head + "Cat,,Dish,,,,,VEG,\n",
		"bad price":    head + "Cat,,Dish,,abc,,,VEG,\n",
		"duplicate":    head + "Cat,,Dish,,10,,,VEG,\nCat,,dish,,12,,,VEG,\n",
		"missing name": head + "Cat,x,,,10,,,VEG,\n",
		"no rows":      head,
	}
	for name, in := range cases {
		if _, err := Parse(strings.NewReader(in)); err == nil {
			t.Errorf("%s: expected an error", name)
		}
	}
}
