package orderimport

import (
	"archive/zip"
	"bytes"
	"fmt"
	"strings"
	"testing"
	"time"
)

// book builds a minimal .xlsx with inline-string cells, one sheet per entry.
func book(t *testing.T, sheets ...[][]string) *bytes.Reader {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for i, rows := range sheets {
		w, err := zw.Create(fmt.Sprintf("xl/worksheets/sheet%d.xml", i+1))
		if err != nil {
			t.Fatal(err)
		}
		var b strings.Builder
		b.WriteString(`<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>`)
		for r, row := range rows {
			fmt.Fprintf(&b, `<row r="%d">`, r+1)
			for c, v := range row {
				if v == "" {
					continue
				}
				fmt.Fprintf(&b, `<c r="%c%d" t="inlineStr"><is><t>%s</t></is></c>`, 'A'+c, r+1, v)
			}
			b.WriteString(`</row>`)
		}
		b.WriteString(`</sheetData></worksheet>`)
		_, _ = w.Write([]byte(b.String()))
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return bytes.NewReader(buf.Bytes())
}

var ordersHeader = []string{"Date", "Customer Name", "Phone No.", "Order No.", "Total Amount", "Payment Type", "Service Charge"}
var itemsHeader = []string{"Date", "Customer Name", "Invoice No.", "Item Name", "Quantity", "Price/Unit", "Discount",
	"Taxable Price/Unit", "Taxable Amount", "CGST", "SGST", "Final Price/Unit", "Amount"}

func ist() *time.Location { return time.FixedZone("IST", 5*3600+1800) }

func TestParseReport(t *testing.T) {
	r := book(t,
		[][]string{
			{"Generated on Nov 24,2026 at 03:54 pm"}, {},
			ordersHeader, {},
			{"24/11/2026", "Cash Sale", "", "3874", "640.00", "Cash", "0.00 (0.0%)"},
			{"25/11/2026", "Ravi", "9876543210", "3875", "1,050.00", "UPI", "50.00 (5.0%)"},
			{},
			{"", "", "", "Total", "1,690.00", "", "50.00"},
		},
		[][]string{
			itemsHeader,
			{"24/11/2026", "Cash Sale", "3874", "Veg Sandwich", "4.0", "100.00", "0.00(0.0%)", "100.00", "400.00", "0.00(0.0%)", "0.00(0.0%)", "100.00", "400.00"},
			{"24/11/2026", "Cash Sale", "3874", "Veg Kathi Roll", "4.0", "60.00", "0.00(0.0%)", "60.00", "240.00", "0.00(0.0%)", "0.00(0.0%)", "60.00", "240.00"},
			{"25/11/2026", "Ravi", "3875", "Chicken Pizza", "2", "500.00", "0.00(0.0%)", "500.00", "1000.00", "0.00(0.0%)", "0.00(0.0%)", "500.00", "1000.00"},
		},
	)
	orders, err := Parse(r, int64(r.Len()), ist())
	if err != nil {
		t.Fatal(err)
	}
	if len(orders) != 2 {
		t.Fatalf("want 2 orders, got %d", len(orders))
	}
	o := orders[0]
	if o.Invoice != "3874" || o.TotalPaise != 64000 || o.PaymentType != "Cash" || o.Customer != "Cash Sale" {
		t.Fatalf("order 1 = %+v", o)
	}
	if !o.Date.Equal(time.Date(2026, 11, 24, 0, 0, 0, 0, ist())) {
		t.Fatalf("date = %v", o.Date)
	}
	if len(o.Lines) != 2 || o.Lines[1].Name != "Veg Kathi Roll" || o.Lines[1].Quantity != 4 || o.Lines[1].UnitPaise != 6000 || o.Lines[1].AmountPaise != 24000 {
		t.Fatalf("lines = %+v", o.Lines)
	}
	if orders[1].ServicePaise != 5000 || orders[1].TotalPaise != 105000 || orders[1].Phone != "9876543210" {
		t.Fatalf("order 2 = %+v", orders[1])
	}
}

func TestParseRejectsMismatchedTotal(t *testing.T) {
	r := book(t,
		[][]string{ordersHeader, {"24/11/2026", "Cash Sale", "", "1", "999.00", "Cash", "0"}},
		[][]string{itemsHeader, {"24/11/2026", "Cash Sale", "1", "Tea", "1", "30", "0", "30", "30", "0", "0", "30", "30.00"}},
	)
	if _, err := Parse(r, int64(r.Len()), ist()); err == nil || !strings.Contains(err.Error(), "don't match") {
		t.Fatalf("want total mismatch error, got %v", err)
	}
}

func TestParseRejectsOrphanItemAndFractionalQty(t *testing.T) {
	r := book(t,
		[][]string{ordersHeader, {"24/11/2026", "Cash Sale", "", "1", "30", "Cash", "0"}},
		[][]string{itemsHeader, {"24/11/2026", "Cash Sale", "2", "Tea", "1", "30", "0", "30", "30", "0", "0", "30", "30"}},
	)
	if _, err := Parse(r, int64(r.Len()), ist()); err == nil || !strings.Contains(err.Error(), "not in the orders sheet") {
		t.Fatalf("want orphan error, got %v", err)
	}
	r = book(t,
		[][]string{ordersHeader, {"24/11/2026", "Cash Sale", "", "1", "45", "Cash", "0"}},
		[][]string{itemsHeader, {"24/11/2026", "Cash Sale", "1", "Tea", "1.5", "30", "0", "30", "45", "0", "0", "30", "45"}},
	)
	if _, err := Parse(r, int64(r.Len()), ist()); err == nil || !strings.Contains(err.Error(), "whole number") {
		t.Fatalf("want quantity error, got %v", err)
	}
}

func TestMoney(t *testing.T) {
	for in, want := range map[string]int64{"640.00": 64000, "0.00(0.0%)": 0, "1,250.50": 125050, "": 0, " 5 ": 500, "0.00 (0.0%)": 0} {
		got, err := money(in)
		if err != nil || got != want {
			t.Errorf("money(%q) = %d, %v; want %d", in, got, err, want)
		}
	}
	if _, err := money("abc"); err == nil {
		t.Error("money(abc) should fail")
	}
}
