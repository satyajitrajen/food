package license

import (
	"testing"
	"time"

	"foodpos/backend/internal/models"
)

func TestSignVerifyRoundTrip(t *testing.T) {
	e := models.Entitlement{
		Status: "active", GraceDays: 7, ValidUntil: time.Now().Add(24 * time.Hour),
	}
	token, err := Sign(e, "license-secret", "jwt-secret")
	if err != nil {
		t.Fatal(err)
	}
	got, ok := Verify(token, "license-secret", "jwt-secret")
	if !ok {
		t.Fatal("token should verify")
	}
	if got.Status != e.Status || got.GraceDays != e.GraceDays {
		t.Fatalf("payload mismatch: %+v", got)
	}
}

func TestVerifyRejectsTamperAndWrongSecret(t *testing.T) {
	e := models.Entitlement{Status: "trial", GraceDays: 7}
	token, err := Sign(e, "s1", "j")
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := Verify(token+"x", "s1", "j"); ok {
		t.Fatal("tampered token must fail")
	}
	if _, ok := Verify(token, "wrong", "j"); ok {
		t.Fatal("wrong secret must fail")
	}
	// Fallback to JWT secret when license secret is unset.
	token2, _ := Sign(e, "", "jwt-abc")
	if _, ok := Verify(token2, "", "jwt-abc"); !ok {
		t.Fatal("jwt-secret fallback should verify")
	}
}
