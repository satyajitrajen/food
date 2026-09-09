// Command loadtest drives order-write traffic (create → item → KOT → pay)
// against a running FoodPOS server and prints latency percentiles.
// Target (PRD NFR): p95 order save < 150 ms at 50 rps.
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

func main() {
	base := flag.String("base", "http://localhost:8080", "base URL")
	staff := flag.String("staff", "st-01", "staff id")
	pin := flag.String("pin", "1234", "staff PIN")
	outlet := flag.String("outlet", "out-01", "outlet id")
	rps := flag.Int("rps", 50, "target order-flows per second")
	duration := flag.Duration("duration", 15*time.Second, "test duration")
	flag.Parse()

	client := &http.Client{Timeout: 10 * time.Second}
	token, err := login(client, *base, *staff, *pin, *outlet)
	if err != nil {
		fmt.Println("login failed:", err)
		return
	}

	var mu sync.Mutex
	latencies := []time.Duration{}
	var okCount, failCount atomic.Int64
	stop := make(chan struct{})
	var wg sync.WaitGroup

	start := time.Now()
	tick := time.NewTicker(time.Second / time.Duration(*rps))
	defer tick.Stop()
	worker := func() {
		defer wg.Done()
		for {
			select {
			case <-stop:
				return
			case <-tick.C:
			}
			t0 := time.Now()
			err := runFlow(client, *base, token, *outlet, fmt.Sprintf("lt-%d-%d-%d", start.UnixMilli(), time.Now().UnixNano(), okCount.Load()))
			elapsed := time.Since(t0)
			mu.Lock()
			latencies = append(latencies, elapsed)
			mu.Unlock()
			if err != nil {
				failCount.Add(1)
			} else {
				okCount.Add(1)
			}
		}
	}

	workers := *rps
	if workers > 200 {
		workers = 200
	}
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go worker()
	}
	time.Sleep(*duration)
	close(stop)
	wg.Wait()

	elapsed := time.Since(start)
	fmt.Printf("flows: %d ok, %d failed in %.1fs (%.1f flows/s)\n",
		okCount.Load(), failCount.Load(), elapsed.Seconds(), float64(okCount.Load())/elapsed.Seconds())
	if len(latencies) == 0 {
		return
	}
	sort.Slice(latencies, func(i, j int) bool { return latencies[i] < latencies[j] })
	pct := func(p float64) time.Duration {
		i := int(float64(len(latencies)-1) * p)
		return latencies[i]
	}
	fmt.Printf("order→pay latency: p50 %v · p95 %v · p99 %v · max %v\n",
		pct(0.50), pct(0.95), pct(0.99), latencies[len(latencies)-1])
}

func login(client *http.Client, base, staff, pin, outlet string) (string, error) {
	body, _ := json.Marshal(map[string]string{"staff_id": staff, "pin": pin, "outlet_id": outlet})
	res, err := client.Post(base+"/api/v1/auth/login", "application/json", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	defer res.Body.Close()
	var out map[string]any
	_ = json.NewDecoder(res.Body).Decode(&out)
	if res.StatusCode != 200 {
		return "", fmt.Errorf("status %d", res.StatusCode)
	}
	tok, _ := out["token"].(string)
	if tok == "" {
		return "", fmt.Errorf("no token")
	}
	return tok, nil
}

func runFlow(client *http.Client, base, token, outlet, idem string) error {
	post := func(path string, payload any) (map[string]any, error) {
		body, _ := json.Marshal(payload)
		req, err := http.NewRequest("POST", base+path, bytes.NewReader(body))
		if err != nil {
			return nil, err
		}
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Bearer "+token)
		req.Header.Set("Idempotency-Key", idem+"-"+path)
		res, err := client.Do(req)
		if err != nil {
			return nil, err
		}
		defer res.Body.Close()
		raw, _ := io.ReadAll(res.Body)
		if res.StatusCode >= 300 {
			return nil, fmt.Errorf("%s -> %d: %s", path, res.StatusCode, strings.TrimSpace(string(raw)))
		}
		var out map[string]any
		_ = json.Unmarshal(raw, &out)
		return out, nil
	}
	order, err := post("/api/v1/orders?outlet_id="+outlet, map[string]any{"type": "takeaway"})
	if err != nil {
		return err
	}
	orderID, _ := order["id"].(string)
	updated, err := post("/api/v1/orders/"+orderID+"/items", map[string]any{
		"menu_item_id": "m-01", "quantity": 1,
	})
	if err != nil {
		return err
	}
	if _, err := post("/api/v1/orders/"+orderID+"/kot", map[string]any{}); err != nil {
		return err
	}
	total, _ := updated["grand_total_paise"].(float64)
	if total <= 0 {
		total = 30000
	}
	if _, err := post("/api/v1/orders/"+orderID+"/pay", map[string]any{
		"method": "cash", "amount_received_paise": int64(total) + 100000,
	}); err != nil {
		return err
	}
	return nil
}
