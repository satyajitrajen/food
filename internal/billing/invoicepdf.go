package billing

// Minimal single-page PDF invoice generator (no external deps). ASCII-safe:
// the rupee symbol is rendered as "INR". Content is plain text lines; layout
// is functional for invoices, not pixel-perfect.

import (
	"bytes"
	"fmt"
	"io"
	"strings"
	"time"

	"foodpos/backend/internal/models"
)

// RenderInvoicePDF writes a simple invoice PDF for a SaaS invoice.
func RenderInvoicePDF(w io.Writer, org models.Organization, inv models.SaaSInvoice) error {
	lines := []string{
		"FOODPOS - INVOICE",
		"====================",
		fmt.Sprintf("Invoice no : %s", inv.InvoiceNo),
		fmt.Sprintf("Date       : %s", inv.PaidAt.UTC().Format("02 Jan 2006 15:04 MST")),
		fmt.Sprintf("Customer   : %s (%s)", org.Name, org.Email),
		fmt.Sprintf("GSTIN      : %s", ascii(org.GSTIN)),
		"",
		"Subscription period:",
		fmt.Sprintf("  %s  ->  %s", fmtTime(inv.PeriodStart), fmtTime(inv.PeriodEnd)),
		"",
		fmt.Sprintf("Base amount     : INR %d", inv.AmountPaise/100+(inv.AmountPaise%100)/100),
		fmt.Sprintf("GST (%.0f%%)      : INR %d", inv.GSTPercent, inv.TaxPaise/100),
		fmt.Sprintf("TOTAL (incl.)   : INR %d", inv.GrossPaise/100),
		"",
		fmt.Sprintf("Paid via %s on %s", inv.Method, inv.PaidAt.UTC().Format("02 Jan 2006")),
		"",
		"Thank you for using FoodPOS.",
	}
	// paise-less display keeps the renderer simple; totals in whole rupees.
	return renderSimplePDF(w, lines)
}

func fmtTime(t *time.Time) string {
	if t == nil {
		return "-"
	}
	return t.UTC().Format("02 Jan 2006")
}

func ascii(s string) string {
	r := strings.NewReplacer(
		"\u20b9", "INR ", "—", "-", "–", "-", "'", "'", "’", "'",
	)
	s = r.Replace(s)
	var b strings.Builder
	for _, c := range s {
		if c >= 32 && c < 127 {
			b.WriteRune(c)
		}
	}
	return b.String()
}

// renderSimplePDF emits a one-page PDF (A4) of Helvetica text lines.
func renderSimplePDF(w io.Writer, lines []string) error {
	content := ""
	size := 10.0
	pageW := 595.0
	top := 800.0

	// Build a simple text stream.
	draw := make([]string, 0, len(lines)*2)
	draw = append(draw, "BT", fmt.Sprintf("/F1 %g Tf", size), fmt.Sprintf("%g %g Td", float64(60), top), "14 TL")
	for _, l := range lines {
		draw = append(draw, escapeText(l)+" T*")
	}
	draw = append(draw, "ET")
	content = strings.Join(draw, "\n")
	if !strings.HasSuffix(content, "\n") {
		content += "\n"
	}

	objects := []string{
		"<< /Type /Catalog /Pages 2 0 R >>",
		fmt.Sprintf("<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
		fmt.Sprintf("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %g %g] /Resources << /Font << /F1 %d 0 R >> >> /Contents 4 0 R >>", pageW, 842.0, 5),
		fmt.Sprintf("<< /Length %d >>\nstream\n%s\nendstream", len(content), content),
		"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
	}

	var out bytes.Buffer
	out.WriteString("%PDF-1.4\n")
	offsets := make([]int, 0, len(objects)+1)
	offsets = append(offsets, 0)
	for i, obj := range objects {
		offsets = append(offsets, out.Len())
		fmt.Fprintf(&out, "%d 0 obj\n%s\nendobj\n", i+1, obj)
	}
	xref := out.Len()
	fmt.Fprintf(&out, "xref\n0 %d\n", len(objects)+1)
	fmt.Fprintf(&out, "0000000000 65535 f \n")
	for _, off := range offsets[1:] {
		fmt.Fprintf(&out, "%010d 00000 n \n", off)
	}
	fmt.Fprintf(&out, "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n", len(objects)+1, xref)
	_, err := w.Write(out.Bytes())
	return err
}

func escapeText(s string) string {
	s = strings.ReplaceAll(s, "\\", "\\\\")
	s = strings.ReplaceAll(s, "(", "\\(")
	s = strings.ReplaceAll(s, ")", "\\)")
	return s
}
