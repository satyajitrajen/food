// Platform admin CLI: direct-database operations for the manual billing flow.
//
//	cmd/admin list [status]
//	cmd/admin show <org_id>
//	cmd/admin activate <org_id> [-days 30] [-method bank] [-amount <paise>] [-ref ""] [-note ""]
//	cmd/admin extend <org_id> [-days 30] [-note ""]
//	cmd/admin suspend <org_id> [-note ""]
//	cmd/admin cancel <org_id> [-note ""]
//	cmd/admin stats
package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"os"

	"foodpos/backend/internal/config"
	"foodpos/backend/internal/db"
	"foodpos/backend/internal/store"
)

func main() {
	cfg := config.Load()
	database, err := db.Open(cfg.DSN)
	if err != nil {
		slog.Error("db open failed", "err", err)
		os.Exit(1)
	}
	defer database.Close()
	if err := db.Migrate(database); err != nil {
		slog.Error("migrations failed", "err", err)
		os.Exit(1)
	}
	st := store.New(database)
	ctx := context.Background()
	if _, err := st.SeedDefaultPlan(ctx); err != nil {
		slog.Error("plan seed failed", "err", err)
		os.Exit(1)
	}

	args := os.Args[1:]
	if len(args) == 0 {
		usage()
		os.Exit(1)
	}
	cmd := args[0]
	rest := args[1:]

	// Only org-taking commands consume a leading org id; "list" keeps its
	// positional argument as a status filter.
	var orgID string
	if cmd != "list" && len(rest) > 0 && !flagHasDash(rest[0]) {
		orgID = rest[0]
		rest = rest[1:]
	}

	fs := flag.NewFlagSet(cmd, flag.ExitOnError)
	days := fs.Int("days", 30, "period days")
	method := fs.String("method", "bank", "bank|upi|razorpay")
	amount := fs.Int64("amount", 0, "amount in paise (0 = plan price)")
	ref := fs.String("ref", "", "payment reference")
	note := fs.String("note", "", "note")
	_ = fs.Parse(rest)
	status := ""
	if cmd == "list" && fs.NArg() > 0 {
		status = fs.Arg(0)
	}

	switch cmd {
	case "list":
		orgs, err := st.ListOrganizations(ctx, status)
		if err != nil {
			fatal(err)
		}
		for _, o := range orgs {
			fmt.Printf("%s\t%s\t%s\n", o.ID, o.Name, o.Status)
		}
	case "show":
		org, err := st.GetOrganization(ctx, orgID)
		if err != nil {
			fatal(err)
		}
		fmt.Printf("org:       %s (%s)\n", org.Name, org.ID)
		fmt.Printf("status:    %s\n", org.Status)
		sub, err := st.GetSubscriptionWithPlan(ctx, orgID)
		if err == nil && sub != nil {
			fmt.Printf("sub:       %s plan=%s cancel=%v\n", sub.Status, sub.PlanID, sub.CancelAtPeriodEnd)
			if sub.TrialEndsAt != nil {
				fmt.Printf("trial end: %s\n", sub.TrialEndsAt)
			}
			if sub.CurrentPeriodEnd != nil {
				fmt.Printf("period end:%s\n", sub.CurrentPeriodEnd)
			}
		}
		invs, _ := st.ListSaaSInvoices(ctx, orgID)
		for _, inv := range invs {
			fmt.Printf("invoice:   %s %d paise (%s) %s\n", inv.InvoiceNo, inv.AmountPaise, inv.Method, inv.PaidAt)
		}
	case "activate":
		sub, inv, err := st.ActivateOrg(ctx, orgID, "cli", *method, *days, *amount, *ref, *note)
		if err != nil {
			fatal(err)
		}
		fmt.Printf("activated: %s -> %s; invoice %s\n", orgID, sub.Status, inv.InvoiceNo)
	case "extend":
		if err := st.ExtendOrg(ctx, orgID, "cli", *days, *note); err != nil {
			fatal(err)
		}
		fmt.Printf("extended:  %s by %d days\n", orgID, *days)
	case "suspend":
		if err := st.SuspendOrg(ctx, orgID, "cli", *note); err != nil {
			fatal(err)
		}
		fmt.Printf("suspended: %s\n", orgID)
	case "cancel":
		if err := st.CancelOrgNow(ctx, orgID, "cli", *note); err != nil {
			fatal(err)
		}
		fmt.Printf("cancelled: %s\n", orgID)
	case "stats":
		orgs, err := st.ListOrganizations(ctx, "")
		if err != nil {
			fatal(err)
		}
		fmt.Printf("total orgs: %d\n", len(orgs))
		counts := map[string]int{}
		for _, o := range orgs {
			counts[o.Status]++
		}
		for k, v := range counts {
			fmt.Printf("  %s: %d\n", k, v)
		}
	default:
		usage()
		os.Exit(1)
	}
}

func usage() {
	fmt.Println(`cmd/admin <command> [org_id] [flags]
commands: list | show | activate | extend | suspend | cancel | stats
flags: -days N -method bank|upi|razorpay -amount <paise> -ref "" -note ""`)
}

func flagHasDash(s string) bool {
	return len(s) > 0 && s[0] == '-'
}

func fatal(err error) {
	slog.Error("operation failed", "err", err)
	os.Exit(1)
}
