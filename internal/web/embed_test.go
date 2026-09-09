package web

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHandlerServesRootAndSPAFallback(t *testing.T) {
	h := Handler()
	// "/" → index.html
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/", nil))
	if rec.Code != 200 || !strings.Contains(rec.Body.String(), "FoodPOS") {
		t.Fatalf("root: status=%d body=%q", rec.Code, rec.Body.String())
	}
	// "/console/login" (client-side route) → SPA fallback index.html
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/console/login", nil))
	if rec.Code != 200 || !strings.Contains(rec.Body.String(), "FoodPOS") {
		t.Fatalf("console route: status=%d body=%q", rec.Code, rec.Body.String())
	}
}

func TestHandlerNeverSwallowsAPIRoutes(t *testing.T) {
	h := Handler()
	for _, p := range []string{"/api/v1/outlets", "/media/menu/x.png", "/healthz", "/ws"} {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, p, nil))
		if rec.Code == 200 && strings.Contains(rec.Body.String(), "<html") {
			t.Fatalf("%s was served HTML by the web handler", p)
		}
	}
}
