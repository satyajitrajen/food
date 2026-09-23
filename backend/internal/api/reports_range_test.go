package api

// Unit coverage for the optional from/to range parsing on /reports/dashboard.
// No database required — parseReportRange is pure.

import (
	"testing"
	"time"
)

func TestParseReportRange(t *testing.T) {
	// Date-only pair: `to` widens to that day's last second (inclusive).
	from, to, err := parseReportRange("2026-09-01", "2026-09-23")
	if err != nil {
		t.Fatalf("date-only range: %v", err)
	}
	if want := time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC); !from.Equal(want) {
		t.Fatalf("from = %v, want %v", from, want)
	}
	if want := time.Date(2026, 9, 23, 23, 59, 59, 0, time.UTC); !to.Equal(want) {
		t.Fatalf("to = %v, want %v", to, want)
	}

	// RFC3339 timestamps pass through, normalized to UTC.
	from, to, err = parseReportRange("2026-09-01T05:30:00+05:30", "2026-09-30T00:00:00Z")
	if err != nil {
		t.Fatalf("rfc3339 range: %v", err)
	}
	if want := time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC); !from.Equal(want) {
		t.Fatalf("from = %v, want %v", from, want)
	}
	if want := time.Date(2026, 9, 30, 0, 0, 0, 0, time.UTC); !to.Equal(want) {
		t.Fatalf("to = %v, want %v", to, want)
	}

	// Empty bounds fall back to open-ended.
	from, to, err = parseReportRange("", "2026-09-23")
	if err != nil {
		t.Fatalf("half-open range: %v", err)
	}
	if !from.IsZero() {
		t.Fatalf("from = %v, want zero value", from)
	}
	if want := time.Date(2026, 9, 23, 23, 59, 59, 0, time.UTC); !to.Equal(want) {
		t.Fatalf("to = %v, want %v", to, want)
	}

	// Garbage is rejected so the handler can answer 400.
	if _, _, err := parseReportRange("not-a-date", "2026-09-23"); err == nil {
		t.Fatal("expected error for invalid from")
	}
	if _, _, err := parseReportRange("2026-09-01", "also-bad"); err == nil {
		t.Fatal("expected error for invalid to")
	}
}
