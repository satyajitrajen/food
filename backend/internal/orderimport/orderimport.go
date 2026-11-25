// Package orderimport parses an "Order Report" exported from another billing app
// (two sheets: one row per order, one row per item) into orders ready to be
// recorded as paid Hishobkr sales. It reads .xlsx with the standard library only
// and touches no database, so the format is unit-tested on its own.
//
// Orders sheet header: Date, Customer Name, Phone No., Order No., Total Amount,
// Payment Type, Service Charge. Items sheet header: Date, Customer Name,
// Invoice No., Item Name, Quantity, Price/Unit, Discount, Taxable Price/Unit,
// Taxable Amount, CGST, SGST, Final Price/Unit, Amount. Money cells may carry a
// percentage suffix ("0.00(0.0%)", "0.00 (0.0%)"); only the amount is used.
package orderimport

import (
	"archive/zip"
	"encoding/xml"
	"fmt"
	"io"
	"math"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

// Line is one item row. Money is paise; amounts are for the whole line.
type Line struct {
	Name          string
	Quantity      int
	UnitPaise     int64
	DiscountPaise int64
	TaxablePaise  int64
	CGSTPaise     int64
	SGSTPaise     int64
	AmountPaise   int64
}

// Order is one sale. Date has no time of day in these reports.
type Order struct {
	Invoice      string
	Date         time.Time // midnight, in the location passed to Parse
	Customer     string
	Phone        string
	PaymentType  string
	TotalPaise   int64
	ServicePaise int64
	Lines        []Line
}

// ItemsPaise is the sum of the line amounts (after discount and tax).
func (o Order) ItemsPaise() int64 {
	var n int64
	for _, l := range o.Lines {
		n += l.AmountPaise
	}
	return n
}

// Parse reads the workbook. Any malformed row aborts with its sheet and row
// number, so a partly understood report is never imported.
func Parse(r io.ReaderAt, size int64, loc *time.Location) ([]Order, error) {
	zr, err := zip.NewReader(r, size)
	if err != nil {
		return nil, fmt.Errorf("not an .xlsx file: %w", err)
	}
	shared, err := sharedStrings(zr)
	if err != nil {
		return nil, err
	}
	var ordersRows, itemRows [][]string
	var ordersStart, itemsStart int
	for _, f := range zr.File {
		if !strings.HasPrefix(f.Name, "xl/worksheets/sheet") || !strings.HasSuffix(f.Name, ".xml") {
			continue
		}
		rows, err := sheetRows(f, shared)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", f.Name, err)
		}
		for i, row := range rows {
			h := headerKey(row)
			if strings.Contains(h, "order no.") && strings.Contains(h, "payment type") {
				ordersRows, ordersStart = rows[i+1:], i+2
				break
			}
			if strings.Contains(h, "invoice no.") && strings.Contains(h, "item name") {
				itemRows, itemsStart = rows[i+1:], i+2
				break
			}
		}
	}
	if ordersRows == nil || itemRows == nil {
		return nil, fmt.Errorf("could not find both the orders sheet (Order No., Payment Type) and the items sheet (Invoice No., Item Name)")
	}

	byInvoice := map[string]*Order{}
	var order []string
	for i, row := range ordersRows {
		if blank(row) || strings.EqualFold(cell(row, 3), "total") {
			continue
		}
		at := fmt.Sprintf("orders sheet row %d", ordersStart+i)
		inv := strings.TrimSpace(cell(row, 3))
		if inv == "" {
			return nil, fmt.Errorf("%s: missing order number", at)
		}
		if _, dup := byInvoice[inv]; dup {
			return nil, fmt.Errorf("%s: order %s appears twice", at, inv)
		}
		d, err := parseDate(cell(row, 0), loc)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", at, err)
		}
		total, err := money(cell(row, 4))
		if err != nil {
			return nil, fmt.Errorf("%s: total: %w", at, err)
		}
		service, err := money(cell(row, 6))
		if err != nil {
			return nil, fmt.Errorf("%s: service charge: %w", at, err)
		}
		byInvoice[inv] = &Order{
			Invoice: inv, Date: d, Customer: strings.TrimSpace(cell(row, 1)), Phone: strings.TrimSpace(cell(row, 2)),
			PaymentType: strings.TrimSpace(cell(row, 5)), TotalPaise: total, ServicePaise: service,
		}
		order = append(order, inv)
	}

	for i, row := range itemRows {
		if blank(row) {
			continue
		}
		at := fmt.Sprintf("items sheet row %d", itemsStart+i)
		inv := strings.TrimSpace(cell(row, 2))
		o := byInvoice[inv]
		if o == nil {
			return nil, fmt.Errorf("%s: invoice %q is not in the orders sheet", at, inv)
		}
		qf, err := strconv.ParseFloat(strings.TrimSpace(cell(row, 4)), 64)
		if err != nil || qf <= 0 || qf != math.Trunc(qf) {
			return nil, fmt.Errorf("%s: quantity %q must be a whole number", at, cell(row, 4))
		}
		var l Line
		l.Name = strings.TrimSpace(cell(row, 3))
		l.Quantity = int(qf)
		if l.Name == "" {
			return nil, fmt.Errorf("%s: missing item name", at)
		}
		for _, f := range []struct {
			col int
			dst *int64
			lbl string
		}{{5, &l.UnitPaise, "price"}, {6, &l.DiscountPaise, "discount"}, {8, &l.TaxablePaise, "taxable amount"},
			{9, &l.CGSTPaise, "CGST"}, {10, &l.SGSTPaise, "SGST"}, {12, &l.AmountPaise, "amount"}} {
			if *f.dst, err = money(cell(row, f.col)); err != nil {
				return nil, fmt.Errorf("%s: %s: %w", at, f.lbl, err)
			}
		}
		o.Lines = append(o.Lines, l)
	}

	out := make([]Order, 0, len(order))
	for _, inv := range order {
		o := byInvoice[inv]
		if len(o.Lines) == 0 {
			return nil, fmt.Errorf("order %s has no item rows", inv)
		}
		// Items + service must add up to the order total (1 rupee rounding slack).
		if d := o.ItemsPaise() + o.ServicePaise - o.TotalPaise; d > 100 || d < -100 {
			return nil, fmt.Errorf("order %s: items (₹%.2f) + service (₹%.2f) don't match total ₹%.2f",
				inv, float64(o.ItemsPaise())/100, float64(o.ServicePaise)/100, float64(o.TotalPaise)/100)
		}
		out = append(out, *o)
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].Date.Before(out[j].Date) })
	return out, nil
}

var moneyRe = regexp.MustCompile(`^-?[\d,]*\.?\d+`)

// money parses "640.00", "1,250.50" or "0.00(0.0%)" into paise; blank is 0.
func money(s string) (int64, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, nil
	}
	m := moneyRe.FindString(s)
	if m == "" {
		return 0, fmt.Errorf("%q is not an amount", s)
	}
	f, err := strconv.ParseFloat(strings.ReplaceAll(m, ",", ""), 64)
	if err != nil {
		return 0, fmt.Errorf("%q is not an amount", s)
	}
	return int64(math.Round(f * 100)), nil
}

// parseDate accepts dd/mm/yyyy (as written) or an Excel serial day number.
func parseDate(s string, loc *time.Location) (time.Time, error) {
	s = strings.TrimSpace(s)
	if t, err := time.ParseInLocation("02/01/2006", s, loc); err == nil {
		return t, nil
	}
	if t, err := time.ParseInLocation("2/1/2006", s, loc); err == nil {
		return t, nil
	}
	if n, err := strconv.ParseFloat(s, 64); err == nil && n > 20000 && n < 80000 {
		d := time.Date(1899, 12, 30, 0, 0, 0, 0, loc).AddDate(0, 0, int(n))
		return d, nil
	}
	return time.Time{}, fmt.Errorf("date %q is not dd/mm/yyyy", s)
}

func headerKey(row []string) string {
	return strings.ToLower(strings.Join(row, "|"))
}

func blank(row []string) bool {
	for _, c := range row {
		if strings.TrimSpace(c) != "" {
			return false
		}
	}
	return true
}

func cell(row []string, i int) string {
	if i < len(row) {
		return row[i]
	}
	return ""
}

// --- minimal .xlsx reading ---

type xmlRich struct {
	T []string `xml:"t"`
	R []struct {
		T string `xml:"t"`
	} `xml:"r"`
}

func (x xmlRich) text() string {
	var b strings.Builder
	for _, t := range x.T {
		b.WriteString(t)
	}
	for _, r := range x.R {
		b.WriteString(r.T)
	}
	return b.String()
}

func sharedStrings(zr *zip.Reader) ([]string, error) {
	for _, f := range zr.File {
		if f.Name != "xl/sharedStrings.xml" {
			continue
		}
		rc, err := f.Open()
		if err != nil {
			return nil, err
		}
		defer rc.Close()
		var doc struct {
			SI []xmlRich `xml:"si"`
		}
		if err := xml.NewDecoder(rc).Decode(&doc); err != nil {
			return nil, fmt.Errorf("sharedStrings: %w", err)
		}
		out := make([]string, len(doc.SI))
		for i, si := range doc.SI {
			out[i] = si.text()
		}
		return out, nil
	}
	return nil, nil
}

func sheetRows(f *zip.File, shared []string) ([][]string, error) {
	rc, err := f.Open()
	if err != nil {
		return nil, err
	}
	defer rc.Close()
	var doc struct {
		Rows []struct {
			C []struct {
				R  string  `xml:"r,attr"`
				T  string  `xml:"t,attr"`
				V  string  `xml:"v"`
				IS xmlRich `xml:"is"`
			} `xml:"c"`
		} `xml:"sheetData>row"`
	}
	if err := xml.NewDecoder(rc).Decode(&doc); err != nil {
		return nil, err
	}
	rows := make([][]string, 0, len(doc.Rows))
	for _, r := range doc.Rows {
		var row []string
		for i, c := range r.C {
			col := colIndex(c.R, i)
			for len(row) <= col {
				row = append(row, "")
			}
			switch c.T {
			case "s":
				if n, err := strconv.Atoi(strings.TrimSpace(c.V)); err == nil && n >= 0 && n < len(shared) {
					row[col] = shared[n]
				}
			case "inlineStr":
				row[col] = c.IS.text()
			default:
				row[col] = c.V
			}
		}
		rows = append(rows, row)
	}
	return rows, nil
}

// colIndex turns "C5" into 2; cells without a reference keep their position.
func colIndex(ref string, fallback int) int {
	n := 0
	for _, ch := range ref {
		if ch < 'A' || ch > 'Z' {
			break
		}
		n = n*26 + int(ch-'A'+1)
	}
	if n == 0 {
		return fallback
	}
	return n - 1
}
