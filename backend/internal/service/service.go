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

// UnitPricePaise computes variant/modifier-aware unit price in paise.
func UnitPricePaise(base int64, variantPrice int64, mods []models.OrderModifier) int64 {
	total := base
	if variantPrice > 0 {
		total = variantPrice
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

// ValidatePayment checks FR-P1/P2 rules before a payment is applied.
func ValidatePayment(o *models.Order, req models.PaymentReq) error {
	if o.Status == "completed" || o.Status == "cancelled" {
		return httpx.NewError(409, "invalid_state", "Order already closed")
	}
	if len(req.Splits) > 0 {
		// Split tender: sum of splits must cover the total; each split
		// names a valid tender.
		sum := int64(0)
		for _, sp := range req.Splits {
			switch sp.Method {
			case "cash", "upi", "card":
			default:
				return httpx.NewError(400, "invalid_method", "split method must be cash, upi or card")
			}
			if sp.Paise < 0 {
				return httpx.ErrInvalidAmount
			}
			sum += sp.Paise
		}
		if sum+5 < o.GrandTotalPaise {
			return httpx.ErrShortPayment
		}
		return nil
	}
	switch req.Method {
	case "cash", "upi", "card":
	default:
		return httpx.NewError(400, "invalid_method", "method must be cash, upi or card")
	}
	if req.Method == "cash" {
		// Cash must cover the total (FR-P2).
		if req.Received+5 < o.GrandTotalPaise { // 5p tolerance
			return httpx.ErrShortPayment
		}
		if req.Received <= 0 && o.GrandTotalPaise > 0 {
			return httpx.ErrInvalidAmount
		}
	}
	// Digital tenders settle for the exact total; Received is informational.
	return nil
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

// ValidateRefund checks FR-P4: 0 < amount ≤ paid; order must be refundable.
func ValidateRefund(o *models.Order, req models.RefundReq) error {
	if req.AmountPaise <= 0 {
		return httpx.ErrInvalidAmount
	}
	paid := o.PaidPaise
	if paid <= 0 {
		paid = o.GrandTotalPaise
	}
	if req.AmountPaise > paid {
		return httpx.NewError(400, "refund_exceeds_paid", "Refund amount exceeds the amount paid")
	}
	if o.Status == "cancelled" {
		return httpx.NewError(409, "invalid_state", "Order is already cancelled/refunded")
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
