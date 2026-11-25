package main

import (
	"bufio"
	"context"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"foodpos/backend/internal/orderimport"
	"foodpos/backend/internal/store"
)

// importOrders records historical sales from another billing app's Order
// Report (.xlsx) as paid orders. Without -apply it only prints the plan.
//
// -map is a text file of "Report item name = Menu item / Option" lines for names
// that don't match the menu on their own (e.g. "Egg Kathi Roll = Kathi Roll / Single Egg").
func importOrders(ctx context.Context, st *store.Store, args []string) {
	fs := flag.NewFlagSet("import-orders", flag.ExitOnError)
	outlet := fs.String("outlet", "", "target outlet id")
	path := fs.String("xlsx", "", "Order Report .xlsx")
	mapPath := fs.String("map", "", "optional aliases file: Report name = Item / Option")
	orderType := fs.String("type", "takeaway", "order type for imported sales: dine_in|takeaway|delivery")
	tz := fs.String("tz", "Asia/Kolkata", "outlet time zone")
	includeDup := fs.Bool("include-duplicates", false, "import even when a same-day, same-total Hishobkr sale exists")
	apply := fs.Bool("apply", false, "write the orders (default: dry run)")
	_ = fs.Parse(args)
	required(fs, "outlet", "xlsx")

	loc, err := time.LoadLocation(*tz)
	if err != nil {
		fatal(err)
	}
	f, err := os.Open(*path)
	if err != nil {
		fatal(err)
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		fatal(err)
	}
	orders, err := orderimport.Parse(f, info.Size(), loc)
	if err != nil {
		fatal(fmt.Errorf("%s: %w", *path, err))
	}

	aliases := map[string]string{}
	if *mapPath != "" {
		mf, err := os.Open(*mapPath)
		if err != nil {
			fatal(err)
		}
		sc := bufio.NewScanner(mf)
		for n := 1; sc.Scan(); n++ {
			line := strings.TrimSpace(sc.Text())
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}
			from, to, ok := strings.Cut(line, "=")
			if !ok {
				fatal(fmt.Errorf("%s line %d: want \"Report name = Item / Option\"", *mapPath, n))
			}
			aliases[strings.Join(strings.Fields(strings.ToLower(from)), " ")] = strings.TrimSpace(to)
		}
		mf.Close()
	}

	rep, err := st.ImportOrders(ctx, *outlet, orders, store.ImportOrdersOptions{
		Apply: *apply, OrderType: *orderType, Source: filepath.Base(*path), Aliases: aliases,
		IncludeDuplicates: *includeDup, Loc: loc,
	})
	if len(rep.Unmatched) > 0 {
		fmt.Println("Not on the menu (add a line to -map for each):")
		for _, n := range rep.Unmatched {
			fmt.Printf("  %s = <Menu item> / <Option>\n", n)
		}
	}
	if err != nil {
		fatal(err)
	}
	counts := map[string]int{}
	var total int64
	for _, r := range rep.Results {
		counts[r.Status]++
		if r.Status == "imported" || r.Status == "would import" {
			total += r.TotalPaise
		}
		detail := ""
		if r.Detail != "" {
			detail = "  (" + r.Detail + ")"
		}
		fmt.Printf("%-12s invoice %-8s ₹%9.2f  %s%s\n", r.Date, r.Invoice, float64(r.TotalPaise)/100, r.Status, detail)
	}
	fmt.Printf("\n%d order(s) in file: %v; ₹%.2f of sales %s\n", len(rep.Results), counts, float64(total)/100,
		map[bool]string{true: "recorded", false: "would be recorded (dry run; add -apply to write)"}[*apply])
}
