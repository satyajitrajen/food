package api

// DB-free contract test: every offline-sync op body in the shared wire
// contract (repo-root contracts/sync_ops.json, also tested by the Flutter
// side) must decode — with httpx.Decode, i.e. DisallowUnknownFields — into
// the Go model the handler uses. A renamed/removed field on either side
// fails here instead of silently dropping data in the outbox.

import (
	"bytes"
	"encoding/json"
	"net/http/httptest"
	"os"
	"sort"
	"testing"

	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/models"
)

type contractOp struct {
	Method string          `json:"method"`
	Path   string          `json:"path"`
	Model  string          `json:"model"`
	Body   json.RawMessage `json:"body"`
}

// contractModels maps the contract's model names to fresh decode targets.
var contractModels = map[string]func() any{
	"Empty":                 func() any { return &struct{}{} },
	"OrderCreate":           func() any { return &models.OrderCreate{} },
	"OrderPatch":            func() any { return &models.OrderPatch{} },
	"OrderItemAdd":          func() any { return &models.OrderItemAdd{} },
	"OrderItemPatch":        func() any { return &models.OrderItemPatch{} },
	"CancelItemReq":         func() any { return &models.CancelItemReq{} },
	"KOTStatusPatch":        func() any { return &models.KOTStatusPatch{} },
	"PaymentReq":            func() any { return &models.PaymentReq{} },
	"RefundReq":             func() any { return &models.RefundReq{} },
	"ShiftOpenReq":          func() any { return &models.ShiftOpenReq{} },
	"ShiftCloseReq":         func() any { return &models.ShiftCloseReq{} },
	"CashMoveReq":           func() any { return &models.CashMoveReq{} },
	"ExpenseCreate":         func() any { return &models.ExpenseCreate{} },
	"CustomerCreate":        func() any { return &models.CustomerCreate{} },
	"CreditBookReq":         func() any { return &models.CreditBookReq{} },
	"StockAdjust":           func() any { return &models.StockAdjust{} },
	"TablePatch":            func() any { return &models.TablePatch{} },
	"MoveTableReq":          func() any { return &models.MoveTableReq{} },
	"MergeTableReq":         func() any { return &models.MergeTableReq{} },
	"Table":                 func() any { return &models.Table{} },
	"Settings":              func() any { return &models.SettingsPatch{} },
	"OutletPatch":           func() any { return &models.OutletPatch{} },
	"MenuItemUpsert":        func() any { return &models.MenuItemUpsert{} },
	"StaffCreate":           func() any { return &models.StaffCreate{} },
	"StaffPatch":            func() any { return &models.StaffPatch{} },
	"InventoryItem":         func() any { return &models.InventoryItem{} },
	"SupplierCreate":        func() any { return &models.SupplierCreate{} },
	"SupplierPaymentCreate": func() any { return &models.SupplierPaymentCreate{} },
	"PurchaseCreate":        func() any { return &models.PurchaseCreate{} },
	"PurchasePatch":         func() any { return &models.PurchasePatch{} },
	"OrderCancelReq":        func() any { return &models.OrderCancelReq{} },
	"ExpensePatch":          func() any { return &models.ExpensePatch{} },
	"CustomerPatch":         func() any { return &models.CustomerPatch{} },
	"InventoryPatch":        func() any { return &models.InventoryPatch{} },
	"SupplierPatch":         func() any { return &models.SupplierPatch{} },
}

func TestSyncOpContract(t *testing.T) {
	raw, err := os.ReadFile("../../../contracts/sync_ops.json")
	if err != nil {
		t.Fatalf("read contract: %v", err)
	}
	var doc struct {
		Ops map[string]contractOp `json:"ops"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		t.Fatalf("parse contract: %v", err)
	}
	if len(doc.Ops) == 0 {
		t.Fatal("contract has no ops")
	}
	names := make([]string, 0, len(doc.Ops))
	for n := range doc.Ops {
		names = append(names, n)
	}
	sort.Strings(names)
	for _, name := range names {
		op := doc.Ops[name]
		t.Run(name, func(t *testing.T) {
			if op.Model == "None" {
				if len(op.Body) != 0 && string(op.Body) != "null" {
					t.Fatalf("model None must have a null body, got %s", op.Body)
				}
				return
			}
			mk, ok := contractModels[op.Model]
			if !ok {
				t.Fatalf("unknown model %q (add it to contractModels)", op.Model)
			}
			req := httptest.NewRequest(op.Method, op.Path, bytes.NewReader(op.Body))
			dst := mk()
			if err := httpx.Decode(req, dst); err != nil {
				t.Fatalf("%s body does not decode into %s: %v\nbody: %s", op.Method+" "+op.Path, op.Model, err, op.Body)
			}
			// Re-encode → decode the original as a generic map and make sure
			// every contract key survived into the model (no silent drops via
			// a field the model ignores).
			back, _ := json.Marshal(dst)
			var got, want map[string]any
			_ = json.Unmarshal(back, &got)
			_ = json.Unmarshal(op.Body, &want)
			for k := range want {
				if arr, isArr := want[k].([]any); isArr && len(arr) == 0 {
					continue // empty list vs omitempty: same meaning
				}
				if _, ok := got[k]; !ok && want[k] != nil {
					t.Errorf("key %q is not carried by %s", k, op.Model)
				}
			}
		})
	}
}

// The KOT/purchase PATCH and the named models above must match what the
// handlers decode — guard against a handler switching back to an ad-hoc
// struct without updating the contract.
func TestContractModelsCoverPaymentFields(t *testing.T) {
	var p models.PaymentReq
	body := []byte(`{"method":"credit","amount_received_paise":0,"customer_id":"c1"}`)
	if err := httpx.Decode(httptest.NewRequest("POST", "/", bytes.NewReader(body)), &p); err != nil {
		t.Fatal(err)
	}
	if p.CustomerID == nil || *p.CustomerID != "c1" || p.Method != "credit" {
		t.Fatalf("decoded %+v", p)
	}
	var d models.CashDenominations
	if err := httpx.Decode(httptest.NewRequest("POST", "/", bytes.NewReader([]byte(`{"d500":1,"coins_paise":1500}`))), &d); err != nil {
		t.Fatal(err)
	}
	if d.CoinsPaise != 1500 {
		t.Fatalf("coins_paise = %d", d.CoinsPaise)
	}
}
