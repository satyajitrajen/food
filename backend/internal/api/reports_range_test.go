package api

// Unit coverage for from/to range parsing shared by /reports/dashboard,
// /orders, /expenses and /attendance. No database required.

import (
	"testing"
	"time"
)

func TestParseRangeOutletTimezone(t *testing.T) {
	ist, err := time.LoadLocation("Asia/Kolkata")
	if err != nil {
		t.Skip("tzdata unavailable: " + err.Error())
	}
	// Date-only pair: IST calendar days; `to` is exclusive of the NEXT
	// local midnight so the whole last day is included.
	from, to, err := parseRange("2026-09-01", "2026-09-23", ist)
	if err != nil {
		t.Fatalf("date-only range: %v", err)
	}
	if want := time.Date(2026, 8, 31, 18, 30, 0, 0, time.UTC); !from.Equal(want) {
		t.Fatalf("from = %v, want %v", from, want)
	}
	if want := time.Date(2026, 9, 23, 18, 30, 0, 0, time.UTC); !to.Equal(want) {
		t.Fatalf("to = %v, want %v", to, want)
	}

	// RFC3339 timestamps pass through, normalized to UTC.
	from, to, err = parseRange("2026-09-01T05:30:00+05:30", "2026-09-30T00:00:00Z", ist)
	if err != nil {
		t.Fatalf("rfc3339 range: %v", err)
	}
	if want := time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC); !from.Equal(want) {
		t.Fatalf("from = %v, want %v", from, want)
	}
	if want := time.Date(2026, 9, 30, 0, 0, 0, 0, time.UTC); !to.Equal(want) {
		t.Fatalf("to = %v, want %v", to, want)
	}

	// Empty bounds stay open-ended.
	from, to, err = parseRange("", "2026-09-23", time.UTC)
	if err != nil {
		t.Fatalf("half-open range: %v", err)
	}
	if from != nil {
		t.Fatalf("from = %v, want nil", from)
	}
	if want := time.Date(2026, 9, 24, 0, 0, 0, 0, time.UTC); !to.Equal(want) {
		t.Fatalf("to = %v, want %v", to, want)
	}

	// Garbage is rejected so the handler can answer 400.
	if _, _, err := parseRange("not-a-date", "2026-09-23", time.UTC); err == nil {
		t.Fatal("expected error for invalid from")
	}
	if _, _, err := parseRange("2026-09-01", "also-bad", time.UTC); err == nil {
		t.Fatal("expected error for invalid to")
	}
}

func TestDayBounds(t *testing.T) {
	ist, err := time.LoadLocation("Asia/Kolkata")
	if err != nil {
		t.Skip("tzdata unavailable: " + err.Error())
	}
	// 20:00 UTC on the 9th is 01:30 IST on the 10th → the IST day is the 10th.
	from, to := dayBounds(time.Date(2026, 10, 9, 20, 0, 0, 0, time.UTC), ist)
	if want := time.Date(2026, 10, 9, 18, 30, 0, 0, time.UTC); !from.Equal(want) {
		t.Fatalf("from = %v, want %v", from, want)
	}
	if want := time.Date(2026, 10, 10, 18, 30, 0, 0, time.UTC); !to.Equal(want) {
		t.Fatalf("to = %v, want %v", to, want)
	}
}
