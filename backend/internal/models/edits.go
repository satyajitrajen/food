package models

// Edit bodies for back-office records. Only the keys sent change.

type CustomerPatch struct {
	Name    *string `json:"name,omitempty"`
	Phone   *string `json:"phone,omitempty"`
	Email   *string `json:"email,omitempty"`
	Address *string `json:"address,omitempty"`
}

type SupplierPatch struct {
	Name     *string `json:"name,omitempty"`
	Mobile   *string `json:"mobile,omitempty"`
	Email    *string `json:"email,omitempty"`
	Category *string `json:"category,omitempty"`
}

// InventoryPatch edits an item's details. Stock moves only through
// /inventory/{id}/adjust so every change is in the stock log.
type InventoryPatch struct {
	Name      *string  `json:"name,omitempty"`
	Unit      *string  `json:"unit,omitempty"`
	MinStock  *float64 `json:"min_stock,omitempty"`
	CostPaise *int64   `json:"cost_paise,omitempty"`
	BatchNo   *string  `json:"batch_no,omitempty"`
	RackNo    *string  `json:"rack_no,omitempty"`
}

// ExpensePatch edits an expense. The payment method can't change (it
// decides whether the drawer was touched); delete and re-add instead.
type ExpensePatch struct {
	Title     *string `json:"title,omitempty"`
	Category  *string `json:"category,omitempty"`
	Amount    *int64  `json:"amount_paise,omitempty"`
	Vendor    *string `json:"vendor,omitempty"`
	Reference *string `json:"reference,omitempty"`
	Note      *string `json:"note,omitempty"`
}

// OrderCancelReq voids an unpaid order. Once the kitchen has a KOT for it a
// manager must approve (manager role, or manager_pin).
type OrderCancelReq struct {
	Reason     string  `json:"reason"`
	ManagerPin *string `json:"manager_pin,omitempty"`
}
