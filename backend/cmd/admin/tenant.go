package main

// Tenant provisioning commands:
//
//	cmd/admin create-org -name "Hotel Green Candle" -email owner@x.in -owner "Owner Name"
//	                     -password '…' -outlet "Balawadi" [-terminal POS-01] [-pin 4821] [-gstin …] [-plan pro]
//	cmd/admin import-menu -outlet <outlet_id> -csv assets/green_candle_menu.csv [-replace]
//	cmd/admin move-outlet -outlet <outlet_id> -to-org <org_id>

import (
	"bufio"
	"context"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"foodpos/backend/internal/auth"
	"foodpos/backend/internal/config"
	"foodpos/backend/internal/menuimport"
	"foodpos/backend/internal/models"
	"foodpos/backend/internal/store"
)

// runTenantCommand handles the provisioning commands; false = not one of them.
func runTenantCommand(ctx context.Context, st *store.Store, cfg config.Config, cmd string, args []string) bool {
	switch cmd {
	case "create-org":
		createOrg(ctx, st, cfg, args)
	case "import-menu":
		importMenu(ctx, st, args)
	case "move-outlet":
		moveOutlet(ctx, st, args)
	case "set-password":
		setPassword(ctx, st, cfg, args)
	case "set-pin":
		setPIN(ctx, st, cfg, args)
	default:
		return false
	}
	return true
}

func required(fs *flag.FlagSet, names ...string) {
	for _, n := range names {
		if strings.TrimSpace(fs.Lookup(n).Value.String()) == "" {
			fmt.Fprintf(os.Stderr, "-%s is required\n", n)
			fs.Usage()
			os.Exit(2)
		}
	}
}

func createOrg(ctx context.Context, st *store.Store, cfg config.Config, args []string) {
	fs := flag.NewFlagSet("create-org", flag.ExitOnError)
	name := fs.String("name", "", "organization (restaurant) name")
	email := fs.String("email", "", "owner login e-mail")
	owner := fs.String("owner", "", "owner full name")
	password := fs.String("password", "", "owner console password (min 8 chars)")
	outlet := fs.String("outlet", "", "first outlet name")
	terminal := fs.String("terminal", "POS-01", "terminal label")
	pin := fs.String("pin", "", "POS admin PIN, 4-6 digits")
	gstin := fs.String("gstin", "", "GSTIN (optional)")
	plan := fs.String("plan", "pro", "plan code")
	_ = fs.Parse(args)
	required(fs, "name", "email", "owner", "password", "outlet", "pin")
	if len(*password) < 8 {
		fatal(fmt.Errorf("password must be at least 8 characters"))
	}
	if n := len(*pin); n < 4 || n > 6 || strings.Trim(*pin, "0123456789") != "" {
		fatal(fmt.Errorf("pin must be 4-6 digits"))
	}
	mgr := auth.New(cfg.JWTSecret, cfg.BcryptCost)
	pwHash, err := mgr.HashPassword(*password)
	if err != nil {
		fatal(err)
	}
	pinHash, err := mgr.HashPIN(*pin)
	if err != nil {
		fatal(err)
	}
	res, err := st.RegisterOrg(ctx, strings.TrimSpace(*name), strings.ToLower(strings.TrimSpace(*email)), *gstin, "",
		strings.TrimSpace(*owner), pwHash, strings.TrimSpace(*outlet), *terminal, pinHash, *plan)
	if err != nil {
		fatal(err)
	}
	fmt.Printf("org:      %s (%s)\n", res.Org.ID, res.Org.Name)
	fmt.Printf("org code: %s   (terminals sign in with this)\n", res.OrgCode)
	fmt.Printf("outlet:   %s (%s)\n", res.Outlet.ID, res.Outlet.Name)
	fmt.Printf("admin:    %s (%s, role %s)\n", res.Staff.ID, res.Staff.Name, res.Staff.Role)
	if res.Subscription != nil {
		fmt.Printf("plan:     %s, status %s\n", *plan, res.Subscription.Status)
	}
}

func importMenu(ctx context.Context, st *store.Store, args []string) {
	fs := flag.NewFlagSet("import-menu", flag.ExitOnError)
	outlet := fs.String("outlet", "", "target outlet id")
	path := fs.String("csv", "", "menu CSV (assets/green_candle_menu.csv format)")
	replace := fs.Bool("replace", false, "soft-delete live items that are not in the file")
	_ = fs.Parse(args)
	required(fs, "outlet", "csv")
	f, err := os.Open(*path)
	if err != nil {
		fatal(err)
	}
	defer f.Close()
	items, err := menuimport.Parse(f)
	if err != nil {
		fatal(fmt.Errorf("%s: %w", *path, err))
	}
	res, err := st.ImportMenu(ctx, *outlet, items, *replace)
	if err != nil {
		fatal(err)
	}
	fmt.Printf("imported %d rows into %s: %d created, %d updated (%d restored), %d removed\n",
		len(items), *outlet, res.Created, res.Updated, res.Restored, res.Removed)
}

func moveOutlet(ctx context.Context, st *store.Store, args []string) {
	fs := flag.NewFlagSet("move-outlet", flag.ExitOnError)
	outlet := fs.String("outlet", "", "outlet id to move")
	toOrg := fs.String("to-org", "", "destination organization id")
	_ = fs.Parse(args)
	required(fs, "outlet", "to-org")
	if err := st.MoveOutlet(ctx, *outlet, *toOrg); err != nil {
		fatal(err)
	}
	fmt.Printf("moved outlet %s to org %s (outlet-bound staff moved; sessions revoked)\n", *outlet, *toOrg)
}

// setPassword sets an owner account's password without the e-mail reset
// flow (e.g. a test account on an address nobody reads). The password is
// read from stdin, never from a flag, so it stays out of shell history.
func setPassword(ctx context.Context, st *store.Store, cfg config.Config, args []string) {
	fs := flag.NewFlagSet("set-password", flag.ExitOnError)
	email := fs.String("email", "", "owner account e-mail")
	_ = fs.Parse(args)
	required(fs, "email")

	acc, err := st.GetAccountByEmail(ctx, strings.ToLower(strings.TrimSpace(*email)))
	if err != nil {
		fatal(fmt.Errorf("no account with e-mail %s", *email))
	}
	password := readSecret("New password (min 8 characters): ")
	if password == "" {
		fatal(fmt.Errorf("no password given"))
	}
	if len(password) < 8 {
		fatal(fmt.Errorf("password must be at least 8 characters"))
	}
	hash, err := auth.New(cfg.JWTSecret, cfg.BcryptCost).HashPassword(password)
	if err != nil {
		fatal(err)
	}
	if err := st.UpdateAccountPassword(ctx, acc.ID, hash); err != nil {
		fatal(err)
	}
	// Signed-in owner sessions keep the old credentials' access; end them.
	_ = st.RevokeAllSessions(ctx, auth.ScopeOwner, acc.ID)
	fmt.Printf("password updated for %s (%s); owner sessions signed out\n", acc.Email, acc.OrgID)
}

// setPIN sets a staff member's POS PIN (4-6 digits), read from stdin like
// set-password, for test terminals whose admin PIN was never noted down.
func setPIN(ctx context.Context, st *store.Store, cfg config.Config, args []string) {
	fs := flag.NewFlagSet("set-pin", flag.ExitOnError)
	staffID := fs.String("staff", "", "staff id")
	_ = fs.Parse(args)
	required(fs, "staff")

	row, err := st.GetStaff(ctx, strings.TrimSpace(*staffID))
	if err != nil {
		fatal(fmt.Errorf("no staff with id %s", *staffID))
	}
	pin := readSecret("New PIN (4-6 digits): ")
	if len(pin) < 4 || len(pin) > 6 || strings.Trim(pin, "0123456789") != "" {
		fatal(fmt.Errorf("PIN must be 4-6 digits"))
	}
	hash, err := auth.New(cfg.JWTSecret, cfg.BcryptCost).HashPIN(pin)
	if err != nil {
		fatal(err)
	}
	if _, err := st.UpdateStaff(ctx, row.ID, models.StaffPatch{}, &hash); err != nil {
		fatal(err)
	}
	fmt.Printf("PIN updated for %s (%s)\n", row.Name, row.ID)
}

// readSecret prompts on stderr and reads one line from stdin, with terminal
// echo off when stdin is a terminal.
func readSecret(prompt string) string {
	fmt.Fprint(os.Stderr, prompt)
	echoOff := exec.Command("stty", "-echo")
	echoOff.Stdin = os.Stdin
	hidden := echoOff.Run() == nil
	line, _ := bufio.NewReader(os.Stdin).ReadString('\n')
	if hidden {
		restore := exec.Command("stty", "echo")
		restore.Stdin = os.Stdin
		_ = restore.Run()
		fmt.Fprintln(os.Stderr)
	}
	return strings.TrimRight(line, "\r\n")
}
