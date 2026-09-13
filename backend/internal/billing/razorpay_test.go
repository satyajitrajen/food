package billing

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
)

// fakeRazorpay records request bodies for the subscription endpoints and
// returns canned ids.
func fakeRazorpay(t *testing.T) (*RazorpayGateway, map[string]string) {
	t.Helper()
	got := map[string]string{}
	mux := http.NewServeMux()
	handle := func(path string, fn func(body []byte, r *http.Request) string) {
		mux.HandleFunc(path, func(w http.ResponseWriter, r *http.Request) {
			raw, _ := io.ReadAll(r.Body)
			got[path+"|"+r.Method] = string(raw)
			if want := "Basic " + base64.StdEncoding.EncodeToString([]byte("key_id:key_secret")); r.Header.Get("Authorization") != want {
				t.Errorf("missing basic auth: %q", r.Header.Get("Authorization"))
			}
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(fn(raw, r)))
		})
	}
	handle("/v1/plans", func([]byte, *http.Request) string { return `{"id":"plan_fake1"}` })
	handle("/v1/subscriptions", func([]byte, *http.Request) string { return `{"id":"sub_fake1","status":"created"}` })
	handle("/v1/subscriptions/sub_fake1/addons", func([]byte, *http.Request) string { return `{}` })
	handle("/v1/subscriptions/sub_fake1/cancel", func([]byte, *http.Request) string { return `{"id":"sub_fake1","status":"cancelled"}` })

	ts := httptest.NewServer(mux)
	t.Cleanup(ts.Close)
	return NewRazorpay("key_id", "key_secret", "", ts.URL), got
}

func TestRazorpaySubscriptionFlow(t *testing.T) {
	gw, got := fakeRazorpay(t)
	ctx := context.Background()

	planID, err := gw.CreatePlan(ctx, "FoodPOS Pro Dining", 235882, "INR", 30)
	if err != nil || planID != "plan_fake1" {
		t.Fatalf("CreatePlan = %q, %v", planID, err)
	}
	var planReq struct {
		Period   string `json:"period"`
		Interval int    `json:"interval"`
		Item     struct {
			Name     string `json:"name"`
			Amount   int64  `json:"amount"`
			Currency string `json:"currency"`
		} `json:"item"`
	}
	if err := json.Unmarshal([]byte(got["/v1/plans|POST"]), &planReq); err != nil {
		t.Fatal(err)
	}
	if planReq.Period != "monthly" || planReq.Interval != 1 ||
		planReq.Item.Amount != 235882 || planReq.Item.Currency != "INR" || planReq.Item.Name != "FoodPOS Pro Dining" {
		t.Fatalf("unexpected plan payload: %+v", planReq)
	}
	annualID, err := gw.CreatePlan(ctx, "FoodPOS Pro Dining (Annual)", 2264184, "INR", 365)
	if err != nil || annualID != "plan_fake1" {
		t.Fatalf("annual CreatePlan = %q, %v", annualID, err)
	}
	var annualReq struct {
		Period string `json:"period"`
	}
	_ = json.Unmarshal([]byte(got["/v1/plans|POST"]), &annualReq) // last call wins
	if annualReq.Period != "yearly" {
		t.Fatalf("365-day plan should map to yearly, got %s", annualReq.Period)
	}

	sub, err := gw.CreateSubscription(ctx, "plan_fake1", "org-1", 12)
	if err != nil || sub.ID != "sub_fake1" || sub.Status != "created" {
		t.Fatalf("CreateSubscription = %+v, %v", sub, err)
	}
	var subReq struct {
		PlanID         string            `json:"plan_id"`
		TotalCount     int               `json:"total_count"`
		CustomerNotify int               `json:"customer_notify"`
		Notes          map[string]string `json:"notes"`
	}
	if err := json.Unmarshal([]byte(got["/v1/subscriptions|POST"]), &subReq); err != nil {
		t.Fatal(err)
	}
	if subReq.PlanID != "plan_fake1" || subReq.TotalCount != 12 || subReq.CustomerNotify != 0 ||
		subReq.Notes["org_id"] != "org-1" {
		t.Fatalf("unexpected subscription payload: %+v", subReq)
	}

	if err := gw.CreateSubscriptionAddon(ctx, "sub_fake1", "FoodPOS registration fee", 10100, "INR"); err != nil {
		t.Fatalf("CreateSubscriptionAddon: %v", err)
	}
	var addonReq struct {
		Item struct {
			Name   string `json:"name"`
			Amount int64  `json:"amount"`
		} `json:"item"`
	}
	if err := json.Unmarshal([]byte(got["/v1/subscriptions/sub_fake1/addons|POST"]), &addonReq); err != nil {
		t.Fatal(err)
	}
	if addonReq.Item.Amount != 10100 || addonReq.Item.Name != "FoodPOS registration fee" {
		t.Fatalf("unexpected addon payload: %+v", addonReq)
	}

	st, err := gw.CancelSubscription(ctx, "sub_fake1", true)
	if err != nil || st != "cancelled" {
		t.Fatalf("CancelSubscription = %q, %v", st, err)
	}
	if got["/v1/subscriptions/sub_fake1/cancel|POST"] != `{"cancel_at_cycle_end":true}` {
		t.Fatalf("unexpected cancel payload: %s", got["/v1/subscriptions/sub_fake1/cancel|POST"])
	}
}

func TestRazorpayAPIErrorPropagates(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("/v1/plans", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error":{"description":"bad amount"}}`))
	})
	ts := httptest.NewServer(mux)
	defer ts.Close()
	gw := NewRazorpay("k", "s", "", ts.URL)
	if _, err := gw.CreatePlan(context.Background(), "X", -5, "INR", 30); err == nil {
		t.Fatal("expected gateway error to propagate")
	}
}
