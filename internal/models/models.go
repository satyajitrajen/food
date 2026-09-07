// Package models defines the wire structures for the FoodPOS API.
// All monetary values are INTEGER PAISE (1 INR = 100 paise) unless the
// field name says otherwise.
package models

import "time"

// ---- Common ----

type Outlet struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Address  string `json:"address"`
	Terminal string `json:"terminal"`
	GSTIN    string `json:"gstin"`
	FSSAI    string `json:"fssai"`
	Phone    string `json:"phone"`
	IsOnline bool   `json:"is_online"`
}

type Staff struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Role      string    `json:"role"` // admin|manager|cashier|waiter
	AvatarURL string    `json:"avatar_url"`
	Mobile    string    `json:"mobile"`
	IsActive  bool      `json:"is_active"`
	CreatedAt time.Time `json:"created_at"`
}

type StaffCreate struct {
	Name      string `json:"name"`
	Role      string `json:"role"`
	PIN       string `json:"pin"`
	AvatarURL string `json:"avatar_url"`
	Mobile    string `json:"mobile"`
}

// StaffPatch is a partial staff update (PATCH /staff/{id}). A non-empty PIN
// resets the PIN (4-6 digits, enforced by the handler).
type StaffPatch struct {
	Name      *string `json:"name,omitempty"`
	Role      *string `json:"role,omitempty"`
	Mobile    *string `json:"mobile,omitempty"`
	AvatarURL *string `json:"avatar_url,omitempty"`
	IsActive  *bool   `json:"is_active,omitempty"`
	PIN       *string `json:"pin,omitempty"`
}

// ---- Tables ----

type Table struct {
	ID                string  `json:"id"`
	OutletID          string  `json:"outlet_id"`
	TableNumber       string  `json:"table_number"`
	Seats             int     `json:"seats"`
	Floor             string  `json:"floor"`
	Status            string  `json:"status"` // available|occupied|reserved|billing|cleaning
	ActiveOrderID     *string `json:"active_order_id"`
	CurrentAmount     int64   `json:"current_amount_paise"`
	RunningMinutes    int     `json:"running_minutes"`
	GuestCount        int     `json:"guest_count"`
	AssignedWaiterID  *string `json:"assigned_waiter_id"`
	MergedWithTableID *string `json:"merged_with_table_id"`
}

type TablePatch struct {
	Status      *string `json:"status,omitempty"`
	GuestCount  *int    `json:"guest_count,omitempty"`
	WaiterID    *string `json:"waiter_id,omitempty"`
}

type MoveTableReq struct {
	ToTableID string `json:"to_table_id"`
}

type MergeTableReq struct {
	SecondaryTableID string `json:"secondary_table_id"`
}

// ---- Menu ----

type ProductVariant struct {
	ID         string `json:"id"`
	MenuItemID string `json:"menu_item_id,omitempty"`
	Name       string `json:"name"`
	PricePaise int64  `json:"price_paise"`
}

type ModifierItem struct {
	ID         string `json:"id"`
	GroupID    string `json:"group_id,omitempty"`
	Name       string `json:"name"`
	PricePaise int64  `json:"price_paise"`
	Sort       int    `json:"sort,omitempty"`
}

type ModifierGroup struct {
	ID            string         `json:"id"`
	MenuItemID    string         `json:"menu_item_id,omitempty"`
	Name          string         `json:"name"`
	IsMultiSelect bool           `json:"is_multi_select"`
	IsRequired    bool           `json:"is_required"`
	Sort          int            `json:"sort,omitempty"`
	Items         []ModifierItem `json:"items"`
}

type MenuItem struct {
	ID            string          `json:"id"`
	OutletID      string          `json:"outlet_id"`
	CategoryID    string          `json:"category_id"`
	Category      string          `json:"category"`
	Name          string          `json:"name"`
	Description   string          `json:"description"`
	PricePaise    int64           `json:"price_paise"`
	IsVeg         bool            `json:"is_veg"`
	ImageURL      string          `json:"image_url"`
	IsBestseller  bool            `json:"is_bestseller"`
	IsAvailable   bool            `json:"is_available"`
	Sort          int             `json:"sort,omitempty"`
	Variants      []ProductVariant `json:"variants"`
	ModifierGroups []ModifierGroup `json:"modifier_groups"`
}

type MenuItemUpsert struct {
	CategoryID     *string `json:"category_id,omitempty"`
	Name           *string `json:"name,omitempty"`
	Description    *string `json:"description,omitempty"`
	PricePaise     *int64  `json:"price_paise,omitempty"`
	IsVeg          *bool   `json:"is_veg,omitempty"`
	ImageURL       *string `json:"image_url,omitempty"`
	IsBestseller   *bool   `json:"is_bestseller,omitempty"`
	IsAvailable    *bool   `json:"is_available,omitempty"`
	Variants       []ProductVariant `json:"variants,omitempty"`
	ModifierGroups []ModifierGroup  `json:"modifier_groups,omitempty"`
}

// ---- Orders ----

type OrderModifier struct {
	ModifierItemID string `json:"modifier_item_id"`
	Name           string `json:"name"`
	PricePaise     int64  `json:"price_paise"`
}

type OrderItem struct {
	ID            string          `json:"id"`
	ClientID      *string         `json:"client_id,omitempty"`
	MenuItemID    string          `json:"menu_item_id"`
	VariantID     *string         `json:"variant_id"`
	Quantity      int             `json:"quantity"`
	UnitPaise     int64           `json:"unit_paise"`
	TotalPaise    int64           `json:"total_paise"`
	Note          *string         `json:"note"`
	IsKOTSent     bool            `json:"is_kot_sent"`
	IsCancelled   bool            `json:"is_cancelled"`
	CancelReason  *string         `json:"cancel_reason"`
	Name          string          `json:"name"`
	Modifiers     []OrderModifier `json:"modifiers"`
}

type Order struct {
	ID               string     `json:"id"`
	ClientID         *string    `json:"client_id,omitempty"`
	OutletID         string     `json:"outlet_id"`
	OrderNumber      string     `json:"order_number"`
	Type             string     `json:"type"`   // dine_in|takeaway|delivery
	Status           string     `json:"status"` // received|preparing|ready|served|billing|completed|cancelled
	TableID          *string    `json:"table_id"`
	TableNumber      *string    `json:"table_number"`
	CustomerName     *string    `json:"customer_name"`
	CustomerPhone    *string    `json:"customer_phone"`
	DeliveryAddress  *string    `json:"delivery_address"`
	WaiterID         *string    `json:"waiter_id"`
	WaiterName       *string    `json:"waiter_name"`
	GuestCount       int        `json:"guest_count"`
	OrderNote        *string    `json:"order_note"`
	SubtotalPaise    int64      `json:"subtotal_paise"`
	DiscountPercent  float64    `json:"discount_percent"`
	DiscountPaise    int64      `json:"discount_paise"`
	DiscountReason   *string    `json:"discount_reason"`
	TaxPercent       float64    `json:"tax_percent"`
	IsTaxInclusive   bool       `json:"is_tax_inclusive"`
	TaxPaise         int64      `json:"tax_paise"`
	ServicePaise     int64      `json:"service_charge_paise"`
	PackagingPaise   int64      `json:"packaging_charge_paise"`
	DeliveryPaise    int64      `json:"delivery_charge_paise"`
	GrandTotalPaise  int64      `json:"grand_total_paise"`
	InvoiceNumber    *string    `json:"invoice_number"`
	PaidAt           *time.Time `json:"paid_at"`
	PaymentMethod    *string    `json:"payment_method"`
	PaidPaise        int64      `json:"paid_paise"`
	ChangePaise      int64      `json:"change_paise"`
	IdempotencyKey   *string    `json:"-"`
	CreatedAt        time.Time  `json:"created_at"`
	UpdatedAt        time.Time  `json:"updated_at"`
	Items            []OrderItem `json:"items"`
}

type OrderCreate struct {
	Type            string  `json:"type"`
	ClientID        *string `json:"client_id,omitempty"`
	TableID         *string `json:"table_id,omitempty"`
	CustomerName    *string `json:"customer_name,omitempty"`
	CustomerPhone   *string `json:"customer_phone,omitempty"`
	DeliveryAddress *string `json:"delivery_address,omitempty"`
	GuestCount      int     `json:"guest_count,omitempty"`
	OrderNote       *string `json:"order_note,omitempty"`
	TaxPercent      *float64 `json:"tax_percent,omitempty"`
}

type OrderItemAdd struct {
	MenuItemID string          `json:"menu_item_id"`
	ClientID   *string         `json:"client_id,omitempty"`
	VariantID  *string         `json:"variant_id,omitempty"`
	Quantity   int             `json:"quantity"`
	Note       *string         `json:"note,omitempty"`
	Modifiers  []OrderModifier `json:"modifiers,omitempty"`
}

type OrderItemPatch struct {
	Quantity   int     `json:"quantity"`
	ManagerPin *string `json:"manager_pin,omitempty"`
}

type OrderPatch struct {
	Status         *string `json:"status,omitempty"`
	OrderNote      *string `json:"order_note,omitempty"`
	GuestCount     *int    `json:"guest_count,omitempty"`
	CustomerName   *string `json:"customer_name,omitempty"`
	DiscountPercent *float64 `json:"discount_percent,omitempty"`
	DiscountPaise  *int64  `json:"discount_paise,omitempty"`
	DiscountReason *string `json:"discount_reason,omitempty"`
	ServicePaise   *int64  `json:"service_charge_paise,omitempty"`
	PackagingPaise *int64  `json:"packaging_charge_paise,omitempty"`
	DeliveryPaise  *int64  `json:"delivery_charge_paise,omitempty"`
	// FR-A3: manager authorization for discounts above threshold.
	ManagerPin *string `json:"manager_pin,omitempty"`
}

type CancelItemReq struct {
	Reason string `json:"reason"`
	// FR-A3: cancelling an item after its KOT was sent requires a manager PIN.
	ManagerPin string `json:"manager_pin,omitempty"`
}

// ---- KOT ----

type KOT struct {
	ID           string         `json:"id"`
	OutletID     string         `json:"outlet_id"`
	KOTNumber    string         `json:"kot_number"`
	OrderID      string         `json:"order_id"`
	Status       string         `json:"status"` // new|preparing|ready|served|cancelled
	WaiterID     *string        `json:"waiter_id"`
	WaiterName   *string        `json:"waiter_name"`
	TableNumber  *string        `json:"table_number"`
	OrderType    string         `json:"order_type"`
	Note         *string        `json:"note"`
	CreatedAt    time.Time      `json:"created_at"`
	Items        []KOTItem      `json:"items"`
}

type KOTItem struct {
	OrderItemID string `json:"order_item_id"`
	Name        string `json:"name"`
	Quantity    int    `json:"quantity"`
}

// ---- Payments ----

type PaymentSplit struct {
	Method string `json:"method"` // cash|upi|card
	Paise  int64  `json:"amount_paise"`
}

type PaymentReq struct {
	Method    string         `json:"method"` // cash|upi|card
	Received  int64          `json:"amount_received_paise"`
	Splits    []PaymentSplit `json:"splits,omitempty"`
	Reference *string        `json:"reference,omitempty"`
}

type RefundReq struct {
	AmountPaise int64  `json:"amount_paise"`
	Reason      string `json:"reason"`
	IsFull      bool   `json:"is_full_refund"`
	Mode        string `json:"mode"` // cash|upi|original
	// FR-A3: refunds are a manager/admin action.
	ManagerPin string `json:"manager_pin,omitempty"`
}

// ---- Shifts ----

type CashDenominations struct {
	D500 int `json:"d500"`
	D200 int `json:"d200"`
	D100 int `json:"d100"`
	D50  int `json:"d50"`
	D20  int `json:"d20"`
	D10  int `json:"d10"`
}

type Shift struct {
	ID             string     `json:"id"`
	OutletID       string     `json:"outlet_id"`
	StaffID        string     `json:"staff_id"`
	StaffName      string     `json:"staff_name"`
	StartedAt      time.Time  `json:"started_at"`
	ClosedAt       *time.Time `json:"closed_at"`
	OpeningPaise   int64      `json:"opening_paise"`
	OpeningNotes   *string    `json:"opening_notes"`
	CashSales      int64      `json:"cash_sales_paise"`
	UPIsales       int64      `json:"upi_sales_paise"`
	CardSales      int64      `json:"card_sales_paise"`
	RefundsCash    int64      `json:"refunds_cash_paise"`
	RefundsDigital int64      `json:"refunds_digital_paise"`
	Expenses       int64      `json:"expenses_paise"`
	CashIn         int64      `json:"cash_in_paise"`
	CashOut        int64      `json:"cash_out_paise"`
	CountedPaise   *int64     `json:"counted_paise"`
	ClosingNotes   *string    `json:"closing_notes"`
	Status         string     `json:"status"` // open|closed
}

// ExpectedCash = opening + cash sales + cash in − cash expenses − cash refunds − cash out.
func (s *Shift) ExpectedCash() int64 {
	return s.OpeningPaise + s.CashSales + s.CashIn - s.Expenses - s.RefundsCash - s.CashOut
}

func (s *Shift) TotalSales() int64 { return s.CashSales + s.UPIsales + s.CardSales }

type ShiftOpenReq struct {
	OpeningPaise  int64             `json:"opening_paise"`
	Notes         *string           `json:"notes,omitempty"`
	Denominations *CashDenominations `json:"denominations,omitempty"`
}

type ShiftCloseReq struct {
	CountedPaise  int64             `json:"counted_paise"`
	Notes         *string           `json:"notes,omitempty"`
	Denominations *CashDenominations `json:"denominations,omitempty"`
}

type CashMoveReq struct {
	Type      string `json:"type"` // cash_in|cash_out
	Amount    int64  `json:"amount_paise"`
	Reason    string `json:"reason"`
	Reference *string `json:"reference,omitempty"`
}

type CashTransaction struct {
	ID        string     `json:"id"`
	ShiftID   string     `json:"shift_id"`
	Type      string     `json:"type"`
	Amount    int64      `json:"amount_paise"`
	Reason    string     `json:"reason"`
	Reference *string    `json:"reference"`
	StaffID   *string    `json:"staff_id"`
	StaffName *string    `json:"staff_name"`
	Ts        *time.Time `json:"ts"`
}

// ---- Expenses / Customers / Inventory ----

type Expense struct {
	ID        string    `json:"id"`
	OutletID  string    `json:"outlet_id"`
	Title     string    `json:"title"`
	Category  string    `json:"category"`
	Amount    int64     `json:"amount_paise"`
	Method    string    `json:"method"`
	Vendor    *string   `json:"vendor"`
	Reference *string   `json:"reference"`
	Note      *string   `json:"note"`
	Ts        time.Time `json:"ts"`
	CreatedBy *string   `json:"created_by"`
}

type ExpenseCreate struct {
	Title     string  `json:"title"`
	Category  string  `json:"category"`
	Amount    int64   `json:"amount_paise"`
	Method    string  `json:"method"`
	Vendor    *string `json:"vendor,omitempty"`
	Reference *string `json:"reference,omitempty"`
	Note      *string `json:"note,omitempty"`
}

type Customer struct {
	ID           string     `json:"id"`
	OutletID     string     `json:"outlet_id"`
	Name         string     `json:"name"`
	PhoneNorm    string     `json:"phone"`
	Email        *string    `json:"email"`
	Address      *string    `json:"address"`
	Visits       int        `json:"visits"`
	LifetimeSpend int64     `json:"lifetime_spend_paise"`
	Outstanding  int64      `json:"outstanding_paise"`
	LastVisit    *time.Time `json:"last_visit"`
}

type CustomerCreate struct {
	Name    string  `json:"name"`
	Phone   string  `json:"phone"`
	Email   *string `json:"email,omitempty"`
	Address *string `json:"address,omitempty"`
}

type InventoryItem struct {
	ID        string  `json:"id"`
	OutletID  string  `json:"outlet_id"`
	Name      string  `json:"name"`
	Unit      string  `json:"unit"`
	Stock     float64 `json:"stock"`
	MinStock  float64 `json:"min_stock"`
	CostPaise int64   `json:"cost_paise"`
}

type StockAdjust struct {
	Delta  float64 `json:"delta"`
	Reason string `json:"reason"`
}

type StockAdjustmentEntry struct {
	ID        string    `json:"id"`
	ItemID    string    `json:"item_id"`
	ItemName  string    `json:"item_name"`
	Delta     float64   `json:"delta"`
	Reason    string    `json:"reason"`
	StaffID   *string   `json:"staff_id"`
	StaffName *string   `json:"staff_name"`
	Ts        time.Time `json:"ts"`
}

// ---- Suppliers / Purchases (P3) ----

type Supplier struct {
	ID            string `json:"id"`
	OutletID      string `json:"outlet_id"`
	Name          string `json:"name"`
	Mobile        string `json:"mobile"`
	Email         *string `json:"email"`
	Category      *string `json:"category"`
	Outstanding   int64  `json:"outstanding_paise"`
}

type SupplierCreate struct {
	Name     string  `json:"name"`
	Mobile   string  `json:"mobile"`
	Email    *string `json:"email,omitempty"`
	Category *string `json:"category,omitempty"`
}

type PurchaseLine struct {
	InventoryItemID string  `json:"inventory_item_id"`
	Name            string  `json:"name,omitempty"`
	Qty             float64 `json:"qty"`
	UnitCostPaise   int64   `json:"unit_cost_paise"`
}

type PurchaseCreate struct {
	InvoiceNo  string         `json:"invoice_no"`
	SupplierID *string        `json:"supplier_id,omitempty"`
	Status     string         `json:"status"` // paid|pending
	TotalPaise int64          `json:"total_paise"`
	Items      []PurchaseLine `json:"items,omitempty"`
}

type Purchase struct {
	ID           string         `json:"id"`
	OutletID     string         `json:"outlet_id"`
	InvoiceNo    string         `json:"invoice_no"`
	SupplierID   *string        `json:"supplier_id"`
	SupplierName string         `json:"supplier_name"`
	Ts           time.Time      `json:"ts"`
	TotalPaise   int64          `json:"total_paise"`
	Status       string         `json:"status"`
	Summary      string         `json:"summary"`
	Items        []PurchaseLine `json:"items,omitempty"`
}

// ---- Customer credit (FR-C1) ----

type CreditBookReq struct {
	Kind        string `json:"kind"` // sale|settlement
	AmountPaise int64  `json:"amount_paise"`
	Reason      string `json:"reason"`
}

type CustomerCreditEntry struct {
	ID        string    `json:"id"`
	OutletID  string    `json:"outlet_id"`
	CustomerID string   `json:"customer_id"`
	Kind      string    `json:"kind"`
	Amount    int64     `json:"amount_paise"`
	Reason    string    `json:"reason"`
	StaffID   *string   `json:"staff_id"`
	StaffName *string   `json:"staff_name"`
	Ts        time.Time `json:"ts"`
}

// ---- Settings & Reports ----

type Settings struct {
	OutletID         string  `json:"outlet_id"`
	RestaurantName   string  `json:"restaurant_name"`
	GSTPercent       float64 `json:"gst_percent"`
	IsGSTInclusive   bool    `json:"is_gst_inclusive"`
	ServicePercent   float64 `json:"service_percent"`
	PackagingPaise   int64   `json:"packaging_paise"`
	DeliveryPaise    int64   `json:"delivery_paise"`
	AutoPrintKOT     bool    `json:"auto_print_kot"`
	AllowReprint     bool    `json:"allow_reprint"`
	BillingPrinter   string  `json:"billing_printer"`
	KitchenPrinter   string  `json:"kitchen_printer"`
	BarPrinter       string  `json:"bar_printer"`
}

type DashboardReport struct {
	SalesPaise     int64                  `json:"sales_paise"`
	OrderCount     int                    `json:"order_count"`
	AOVPaise       int64                  `json:"aov_paise"`
	ExpensesPaise  int64                  `json:"expenses_paise"`
	CashDrawerPaise int64                 `json:"cash_drawer_paise"`
	PendingKOTs    int                    `json:"pending_kots"`
	FreeTables     int                    `json:"free_tables"`
	OccupiedTables int                    `json:"occupied_tables"`
	SalesByType    map[string]int64       `json:"sales_by_type"`
	SalesByTender  map[string]int64       `json:"sales_by_tender"`
	TopCategories  []CategorySales        `json:"top_categories"`
}

type CategorySales struct {
	Category    string `json:"category"`
	Revenue     int64  `json:"revenue_paise"`
	Quantity    int    `json:"quantity"`
}

type ZReport struct {
	Shift          Shift             `json:"shift"`
	ExpectedCash   int64             `json:"expected_cash_paise"`
	CountedCash    int64             `json:"counted_cash_paise"`
	DifferencePaise int64            `json:"difference_paise"`
	TotalSales     int64             `json:"total_sales_paise"`
}
