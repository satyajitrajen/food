package service

import (
	"testing"

	"foodpos/backend/internal/models"
)

func TestApplyBillingBasic(t *testing.T) {
	o := &models.Order{
		Items: []models.OrderItem{
			{TotalPaise: 28000, Quantity: 1},
			{TotalPaise: 20000, Quantity: 4},
		},
		TaxPercent: 5.0,
	}
	ApplyBilling(o)
	if o.SubtotalPaise != 48000 {
		t.Fatalf("subtotal = %d, want 48000", o.SubtotalPaise)
	}
	if o.TaxPaise != 2400 {
		t.Fatalf("tax = %d, want 2400", o.TaxPaise)
	}
	if o.GrandTotalPaise != 50400 {
		t.Fatalf("grand total = %d, want 50400", o.GrandTotalPaise)
	}
}

func TestApplyBillingTaxIncludesServiceCharge(t *testing.T) {
	o := &models.Order{
		Items:        []models.OrderItem{{TotalPaise: 10000}},
		TaxPercent:   5.0,
		ServicePaise: 1000, // service charge attracts GST
	}
	ApplyBilling(o)
	// net 100 + SC 10 = 110 → tax 5.50 → total 115.50
	if o.TaxPaise != 550 {
		t.Fatalf("tax = %d, want 550", o.TaxPaise)
	}
	if o.GrandTotalPaise != 11550 {
		t.Fatalf("grand total = %d, want 11550", o.GrandTotalPaise)
	}
}

func TestApplyBillingInclusiveGST(t *testing.T) {
	o := &models.Order{
		Items:          []models.OrderItem{{TotalPaise: 10500}}, // price contains GST
		TaxPercent:     5.0,
		IsTaxInclusive: true,
		PackagingPaise: 500,
	}
	ApplyBilling(o)
	// Tax is extracted from the taxed base (net only — packaging is not
	// taxed): 10500·5/105 = 500. Grand total = menu price + packaging.
	if o.TaxPaise != 500 {
		t.Fatalf("tax = %d, want extracted 500", o.TaxPaise)
	}
	if o.GrandTotalPaise != 11000 {
		t.Fatalf("grand total = %d, want 11000 (10500 + 500 packaging, no tax on top)", o.GrandTotalPaise)
	}

	// With a discount, extraction applies to the discounted base.
	d := &models.Order{
		Items:          []models.OrderItem{{TotalPaise: 10500}},
		TaxPercent:     5.0,
		IsTaxInclusive: true,
		DiscountPaise:  1050,
	}
	ApplyBilling(d)
	// net = 9450 → tax = 9450·5/105 = 450; total = 9450
	if d.TaxPaise != 450 {
		t.Fatalf("tax = %d, want 450", d.TaxPaise)
	}
	if d.GrandTotalPaise != 9450 {
		t.Fatalf("grand total = %d, want 9450", d.GrandTotalPaise)
	}
}

func TestApplyBillingDiscountClamps(t *testing.T) {
	// Percent discount capped at 100.
	o := &models.Order{
		Items:           []models.OrderItem{{TotalPaise: 10000}},
		DiscountPercent: 150,
		TaxPercent:      5,
	}
	ApplyBilling(o)
	if o.DiscountPaise != 10000 || o.GrandTotalPaise != 0 {
		t.Fatalf("percent clamp failed: discount=%d total=%d", o.DiscountPaise, o.GrandTotalPaise)
	}

	// Amount discount capped at subtotal.
	o2 := &models.Order{
		Items:        []models.OrderItem{{TotalPaise: 10000}},
		DiscountPaise: 25000,
		TaxPercent:   5,
	}
	ApplyBilling(o2)
	if o2.DiscountPaise != 10000 || o2.GrandTotalPaise != 0 {
		t.Fatalf("amount clamp failed: discount=%d total=%d", o2.DiscountPaise, o2.GrandTotalPaise)
	}

	// Negative amount treated as zero.
	o3 := &models.Order{
		Items:        []models.OrderItem{{TotalPaise: 10000}},
		DiscountPaise: -5000,
		TaxPercent:   5,
	}
	ApplyBilling(o3)
	if o3.DiscountPaise != 0 || o3.GrandTotalPaise != 10500 {
		t.Fatalf("negative discount not neutralized: discount=%d total=%d", o3.DiscountPaise, o3.GrandTotalPaise)
	}
}

func TestApplyBillingIgnoresCancelledItems(t *testing.T) {
	o := &models.Order{
		Items: []models.OrderItem{
			{TotalPaise: 10000},
			{TotalPaise: 20000, IsCancelled: true},
		},
		TaxPercent: 5,
	}
	ApplyBilling(o)
	if o.SubtotalPaise != 10000 || o.GrandTotalPaise != 10500 {
		t.Fatalf("cancelled item counted: subtotal=%d total=%d", o.SubtotalPaise, o.GrandTotalPaise)
	}
}

func TestKOTStateMachine(t *testing.T) {
	valid := map[string][]string{
		"new":       {"preparing", "ready", "cancelled"},
		"preparing": {"ready", "cancelled"},
		"ready":     {"served", "cancelled"},
	}
	for from, tos := range valid {
		for _, to := range tos {
			if err := ValidateKOTTransition(from, to); err != nil {
				t.Fatalf("expected %s→%s allowed, got %v", from, to, err)
			}
		}
	}
	invalid := [][2]string{
		{"new", "served"}, {"served", "preparing"}, {"cancelled", "new"}, {"ready", "preparing"},
	}
	for _, p := range invalid {
		if err := ValidateKOTTransition(p[0], p[1]); err == nil {
			t.Fatalf("expected %s→%s to be rejected", p[0], p[1])
		}
	}
}

func TestValidatePaymentShortCash(t *testing.T) {
	o := &models.Order{GrandTotalPaise: 10000}
	err := ValidatePayment(o, models.PaymentReq{Method: "cash", Received: 5000})
	if err == nil {
		t.Fatal("short cash payment must be rejected")
	}
	if err := ValidatePayment(o, models.PaymentReq{Method: "cash", Received: 10000}); err != nil {
		t.Fatalf("exact cash should pass: %v", err)
	}
	if err := ValidatePayment(o, models.PaymentReq{Method: "upi", Received: 0}); err != nil {
		t.Fatalf("digital tender covers total implicitly: %v", err)
	}
	if err := ValidatePayment(o, models.PaymentReq{Method: "cash", Received: 12000}); err != nil {
		t.Fatalf("over-tender should pass: %v", err)
	}
}

func TestValidatePaymentSplitTender(t *testing.T) {
	o := &models.Order{GrandTotalPaise: 10000}
	err := ValidatePayment(o, models.PaymentReq{
		Splits: []models.PaymentSplit{{Method: "cash", Paise: 4000}, {Method: "upi", Paise: 6000}},
	})
	if err != nil {
		t.Fatalf("exact split should pass: %v", err)
	}
	err = ValidatePayment(o, models.PaymentReq{
		Splits: []models.PaymentSplit{{Method: "cash", Paise: 4000}},
	})
	if err == nil {
		t.Fatal("split under total must be rejected")
	}
}

func TestComputeChange(t *testing.T) {
	o := &models.Order{GrandTotalPaise: 10000}
	received, change := ComputeChange(o, models.PaymentReq{Method: "cash", Received: 15000})
	if received != 15000 || change != 5000 {
		t.Fatalf("cash change wrong: received=%d change=%d", received, change)
	}
	received, change = ComputeChange(o, models.PaymentReq{Method: "upi"})
	if received != 10000 || change != 0 {
		t.Fatalf("digital change wrong: received=%d change=%d", received, change)
	}
}

func TestValidateRefund(t *testing.T) {
	o := &models.Order{GrandTotalPaise: 10000, PaidPaise: 10000, Status: "completed"}
	if err := ValidateRefund(o, models.RefundReq{AmountPaise: 10000}); err != nil {
		t.Fatalf("full refund should pass: %v", err)
	}
	if err := ValidateRefund(o, models.RefundReq{AmountPaise: 15000}); err == nil {
		t.Fatal("refund above paid must be rejected")
	}
	if err := ValidateRefund(o, models.RefundReq{AmountPaise: 0}); err == nil {
		t.Fatal("zero refund must be rejected")
	}
	cancelled := &models.Order{GrandTotalPaise: 10000, PaidPaise: 10000, Status: "cancelled"}
	if err := ValidateRefund(cancelled, models.RefundReq{AmountPaise: 100}); err == nil {
		t.Fatal("double refund of cancelled order must be rejected")
	}
}

func TestRefundIsCash(t *testing.T) {
	cash := "cash"
	upi := "upi"
	cases := []struct {
		order *string
		mode  string
		want  bool
	}{
		{&cash, "original", true},
		{&upi, "original", false},
		{&upi, "cash", true},   // refund issued in cash leaves the drawer
		{&cash, "upi", false},  // refund issued digitally doesn't
	}
	for i, c := range cases {
		if got := RefundIsCash(c.order, c.mode); got != c.want {
			t.Fatalf("case %d: got %v want %v", i, got, c.want)
		}
	}
}
