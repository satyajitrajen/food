package api

// Customer-facing digital menu (FR: scan QR → open the menu). A single public
// page per outlet: /m/{outlet_id}. No auth — it is the same menu a guest
// would see on the table card. Renders a small, self-contained HTML page
// grouped by category with veg/non-veg marks; media URLs are resolved
// against the same host.

import (
	"fmt"
	"html"
	"net/http"
	"sort"
	"strings"

	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/models"
)

func (s *Server) handleCustomerMenu(w http.ResponseWriter, r *http.Request) {
	outletID := pathID(r, "outletID")
	outlet, err := s.Store.GetOutlet(r.Context(), outletID)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	items, err := s.Store.ListMenu(r.Context(), outletID, "")
	if err != nil {
		httpx.ErrorJSON(w, r, err)
		return
	}

	// Group by category, keep stable sort order.
	cats := []string{}
	byCat := map[string][]models.MenuItem{}
	for i := range items {
		m := items[i]
		c := strings.TrimSpace(m.Category)
		if c == "" {
			c = "Menu"
		}
		if _, ok := byCat[c]; !ok {
			cats = append(cats, c)
		}
		byCat[c] = append(byCat[c], m)
	}
	sort.Strings(cats)

	var b strings.Builder
	b.WriteString(`<!DOCTYPE html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>`)
	b.WriteString(html.EscapeString(outlet.Name))
	b.WriteString(` — Menu</title><style>
body{font-family:system-ui,-apple-system,sans-serif;margin:0;background:#faf7f2;color:#1f2937}
header{background:#2d6a4f;color:#fff;padding:20px 16px}
h1{margin:0;font-size:20px} .sub{opacity:.85;font-size:13px;margin-top:2px}
main{max-width:640px;margin:0 auto;padding:12px 16px 48px}
h2{font-size:15px;margin:22px 0 8px;color:#2d6a4f;text-transform:uppercase;letter-spacing:.5px}
.row{display:flex;gap:10px;align-items:flex-start;padding:10px 0;border-bottom:1px solid #eee}
.mark{width:14px;height:14px;border:1.5px solid;border-radius:3px;padding:2px;flex:none;margin-top:3px}
.mark i{display:block;width:100%;height:100%;border-radius:50%}
.veg{border-color:#2d6a4f}.veg span{background:#2d6a4f}
.nonveg{border-color:#c0392b}.nonveg span{background:#c0392b}
.name{font-weight:700;font-size:15px}.desc{font-size:12px;color:#6b7280;margin-top:2px}
.price{margin-left:auto;font-weight:800;color:#2d6a4f;white-space:nowrap}
.tag{display:inline-block;background:#f59e0b;color:#fff;font-size:10px;font-weight:700;padding:1px 6px;border-radius:8px;margin-left:6px}
.out{color:#9ca3af;text-decoration:line-through}
footer{text-align:center;color:#9ca3af;font-size:11px;margin-top:28px}
</style></head><body>`)
	b.WriteString(`<header><h1>`)
	b.WriteString(html.EscapeString(outlet.Name))
	b.WriteString(`</h1><div class="sub">Menu · Scan. Browse. Order at the counter.</div></header><main>`)

	for _, c := range cats {
		b.WriteString(`<h2>`)
		b.WriteString(html.EscapeString(c))
		b.WriteString(`</h2>`)
		for _, m := range byCat[c] {
			cls := "mark nonveg"
			inner := `<span></span>`
			if m.IsVeg {
				cls = "mark veg"
			}
			unavailable := !m.IsAvailable
			b.WriteString(`<div class="row"><div class="`)
			b.WriteString(cls)
			b.WriteString(`">`)
			b.WriteString(inner)
			b.WriteString(`</div><div><div class="name">`)
			b.WriteString(html.EscapeString(m.Name))
			if m.IsBestseller {
				b.WriteString(`<span class="tag">BESTSELLER</span>`)
			}
			if unavailable {
				b.WriteString(`<span class="tag" style="background:#9ca3af">UNAVAILABLE</span>`)
			}
			b.WriteString(`</div>`)
			if m.Description != "" {
				b.WriteString(`<div class="desc">`)
				b.WriteString(html.EscapeString(m.Description))
				b.WriteString(`</div>`)
			}
			if len(m.Variants) > 0 {
				b.WriteString(`<div class="desc">`)
				for i, v := range m.Variants {
					if i > 0 {
						b.WriteString(" · ")
					}
					b.WriteString(html.EscapeString(v.Name + " ₹" + rupees(v.PricePaise)))
				}
				b.WriteString(`</div>`)
			}
			b.WriteString(`</div><div class="price">`)
			b.WriteString("₹" + rupees(m.PricePaise))
			b.WriteString(`</div></div>`)
		}
	}
	b.WriteString(`<footer>Powered by Hishobkr POS</footer></main></body></html>`)

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = w.Write([]byte(b.String()))
}

func rupees(p int64) string {
	return fmt.Sprintf("%.0f", float64(p)/100)
}
