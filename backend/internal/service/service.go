// Package service holds the business rules: order billing math (in paise),
// KOT state machine, payment and refund validation.
package service

import (
	"math"

	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/models"
	"foodpos/backend/internal/store"
)

// RoundPaise converts a float rupee amount to integer paise (half-up).
func RoundPaise(rupees float64) int64 {
	return int64(math.Round(rupees * 100))
}

// ApplyBilling recomputes subtotal → discount → tax → charges → grandTotal.
// PRD FR-O3: GST base = (subtotal − discount) + service charge.
// Discounts clamp: percent [0,100], amount [0, subtotal].
// Inclusive pricing (IsTaxInclusive): menu prices already contain GST, so the
// tax is EXTRACTED from the discounted base (tax = base·pct/(100+pct)) and the
// grand total is the discounted base + charges, not base + tax.
func ApplyBilling(o *models.Order) {
	subtotal := int64(0)
	for i := range o.Items {
		if o.Items[i].IsCancelled {
			continue
		}
		subtotal += o.Items[i].TotalPaise
	}
	o.SubtotalPaise = subtotal

	// Discount: percent wins when > 0; clamp both.
	discount := int64(0)
	if o.DiscountPercent > 0 {
		pct := math.Min(math.Max(o.DiscountPercent, 0), 100)
		o.DiscountPercent = pct
		discount = int64(math.Round(float64(subtotal) * pct / 100))
	} else {
		o.DiscountPercent = 0
		if o.DiscountPaise < 0 {
			o.DiscountPaise = 0
		}
		discount = o.DiscountPaise
	}
	if discount > subtotal {
		discount = subtotal
	}
	o.DiscountPaise = discount

	net := subtotal - discount
	if net < 0 {
		net = 0
	}

	// A service percent (settings default on dine-in) derives the charge
	// from the discounted net on every pass; 0 keeps the flat amount.
	if o.ServicePercent > 0 {
		pct := math.Min(o.ServicePercent, 100)
		o.ServicePaise = int64(math.Round(float64(net) * pct / 100))
	}
	charges := o.ServicePaise
	if charges < 0 {
		charges = 0
		o.ServicePaise = 0
	}
	if o.PackagingPaise < 0 {
		o.PackagingPaise = 0
	}
	if o.DeliveryPaise < 0 {
		o.DeliveryPaise = 0
	}

	taxBase := net + charges
	if o.IsTaxInclusive {
		tax := int64(0)
		if taxBase > 0 && o.TaxPercent > 0 {
			tax = int64(math.Round(float64(taxBase) * o.TaxPercent / (100 + o.TaxPercent)))
		}
		o.TaxPaise = tax
		// Tax already sits inside (net + service); only non-taxed charges
		// come on top.
		o.GrandTotalPaise = net + o.ServicePaise + o.PackagingPaise + o.DeliveryPaise
		return
	}

	tax := int64(math.Round(float64(taxBase) * o.TaxPercent / 100))
	if tax < 0 {
		tax = 0
	}
	o.TaxPaise = tax

	o.GrandTotalPaise = net + tax + o.ServicePaise + o.PackagingPaise + o.DeliveryPaise
}

// UnitPricePaise computes variant/modifier-aware unit price in paise. A
// chosen variant's price replaces the base price, including a ₹0 variant.
func UnitPricePaise(base int64, variantPrice *int64, mods []models.OrderModifier) int64 {
	total := base
	if variantPrice != nil {
		total = *variantPrice
	}
	for _, m := range mods {
		total += m.PricePaise
	}
	return total
}

// ---- KOT state machine ----

func ValidateKOTTransition(from, to string) error {
	if !store.KOTTransitionAllowed(from, to) {
		return httpx.NewError(409, "invalid_kot_transition",
			"Cannot move KOT from "+from+" to "+to)
	}
	return nil
}

// ---- Payment validation ----

// IsClosed reports whether an order can no longer be paid or edited.
func IsClosed(status string) bool {
	return status == "completed" || status == "cancelled" || status == "refunded"
}

// payTolerance absorbs sub-rupee rounding between client and server totals.
const payTolerance = 5

// ValidatePayment checks FR-P1/P2 rules before a payment is applied.
func ValidatePayment(o *models.Order, req models.PaymentReq) error {
	_, err := PlanPayment(o, req)
	return err
}

// PaymentPlan is what a validated payment books: the tender legs (sum ≈
// grand total, change already taken off the cash leg), what the customer
// handed over and the change returned.
type PaymentPlan struct {
	Legs     []models.PaymentSplit
	Received int64
	Change   int64
}

// PlanPayment validates a payment against an order and derives the legs to
// book per tender. Credit has no legs (the total goes to the customer's
// outstanding instead of the drawer).
func PlanPayment(o *models.Order, req models.PaymentReq) (PaymentPlan, error) {
	total := o.GrandTotalPaise
	if IsClosed(o.Status) {
		return PaymentPlan{}, httpx.NewError(409, "already_paid", "Order is already paid or closed")
	}
	if len(req.Splits) > 0 {
		sum := int64(0)
		legs := make([]models.PaymentSplit, 0, len(req.Splits))
		cashIdx := -1
		for _, sp := range req.Splits {
			switch sp.Method {
			case "cash", "upi", "card":
			default:
				return PaymentPlan{}, httpx.NewError(400, "invalid_method", "split method must be cash, upi or card")
			}
			if sp.Paise < 0 {
				return PaymentPlan{}, httpx.ErrInvalidAmount
			}
			sum += sp.Paise
			if sp.Method == "cash" && cashIdx < 0 {
				cashIdx = len(legs)
			}
			legs = append(legs, sp)
		}
		if sum+payTolerance < total {
			return PaymentPlan{}, httpx.ErrShortPayment
		}
		change := int64(0)
		if over := sum - total; over > 0 {
			// Only cash can be over-tendered (change comes out of the drawer).
			if cashIdx < 0 || legs[cashIdx].Paise < over {
				return PaymentPlan{}, httpx.NewError(400, "overpayment", "Digital split legs exceed the bill total")
			}
			legs[cashIdx].Paise -= over
			change = over
		}
		return PaymentPlan{Legs: legs, Received: sum, Change: change}, nil
	}
	switch req.Method {
	case "cash":
		if req.Received <= 0 && total > 0 {
			return PaymentPlan{}, httpx.ErrInvalidAmount
		}
		if req.Received+payTolerance < total { // FR-P2: cash must cover the total
			return PaymentPlan{}, httpx.ErrShortPayment
		}
		change := req.Received - total
		if change < 0 {
			change = 0
		}
		return PaymentPlan{Legs: []models.PaymentSplit{{Method: "cash", Paise: total}}, Received: req.Received, Change: change}, nil
	case "upi", "card":
		// Digital tenders settle for the exact total; Received is informational.
		return PaymentPlan{Legs: []models.PaymentSplit{{Method: req.Method, Paise: total}}, Received: total}, nil
	case "credit":
		if req.CustomerID == nil || *req.CustomerID == "" {
			return PaymentPlan{}, httpx.NewError(400, "invalid_customer", "customer_id is required for credit payments")
		}
		return PaymentPlan{}, nil
	default:
		return PaymentPlan{}, httpx.NewError(400, "invalid_method", "method must be cash, upi, card or credit")
	}
}

// ComputeChange returns change due for a cash payment (0 for digital).
func ComputeChange(o *models.Order, req models.PaymentReq) (received int64, change int64) {
	if req.Method == "cash" {
		change = req.Received - o.GrandTotalPaise
		if change < 0 {
			change = 0
		}
		return req.Received, change
	}
	return o.GrandTotalPaise, 0
}

// ValidateRefund checks FR-P4: 0 < amount ≤ total − refunded (a full refund
// may omit the amount); order must be refundable.
func ValidateRefund(o *models.Order, req models.RefundReq) error {
	if req.IsFull && req.AmountPaise == 0 {
		req.AmountPaise = o.GrandTotalPaise - o.RefundedPaise
	}
	if req.AmountPaise <= 0 {
		return httpx.ErrInvalidAmount
	}
	switch req.Mode {
	case "", "cash", "upi", "original":
	default:
		return httpx.NewError(400, "invalid_mode", "mode must be cash, upi or original")
	}
	if o.Status == "cancelled" || o.Status == "refunded" {
		return httpx.NewError(409, "invalid_state", "Order is already cancelled/refunded")
	}
	// Cap = grand total − already refunded (never paid_paise: that includes
	// cash change handed back).
	if req.AmountPaise > o.GrandTotalPaise-o.RefundedPaise {
		return httpx.NewError(400, "refund_exceeds_total", "Refund exceeds the bill total still refundable")
	}
	return nil
}

// RefundIsCash decides whether the refund leaves the physical drawer.
func RefundIsCash(orderMethod *string, mode string) bool {
	switch mode {
	case "cash":
		return true
	case "upi":
		return false
	default: // original
		return orderMethod != nil && *orderMethod == "cash"
	}
}
