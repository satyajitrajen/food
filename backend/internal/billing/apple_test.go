package billing_test

import (
	"crypto/x509"
	"encoding/pem"
	"os"
	"strings"
	"testing"
	"time"

	"foodpos/backend/internal/billing"
	"foodpos/backend/internal/billing/appletest"
)

func TestAppleVerifyTransaction(t *testing.T) {
	s := appletest.NewSigner(t)
	v := billing.NewAppleVerifierWithRoot("com.example.app", s.Root)
	exp := time.Now().Add(365 * 24 * time.Hour).UnixMilli()
	jws := s.Sign(t, map[string]any{
		"transactionId": "2000001", "originalTransactionId": "1000001",
		"bundleId": "com.example.app", "productId": "pro.yearly",
		"expiresDate": exp, "price": 1999000, "currency": "INR",
	})
	tx, err := v.VerifyTransaction(jws)
	if err != nil {
		t.Fatalf("verify: %v", err)
	}
	if tx.OriginalTransactionID != "1000001" || tx.PricePaise() != 199900 || tx.Expires().UnixMilli() != exp {
		t.Fatalf("decoded wrong: %+v", tx)
	}

	// Tampered payload: signature must fail.
	parts := strings.Split(jws, ".")
	other := strings.Split(s.Sign(t, map[string]any{"bundleId": "com.example.app", "productId": "free"}), ".")
	if _, err := v.VerifyTransaction(parts[0] + "." + other[1] + "." + parts[2]); err == nil {
		t.Fatal("tampered payload verified")
	}
	// Wrong app.
	if _, err := billing.NewAppleVerifierWithRoot("com.other", s.Root).VerifyTransaction(jws); err == nil {
		t.Fatal("foreign bundle verified")
	}
	// Untrusted root (a different fake chain).
	if _, err := billing.NewAppleVerifierWithRoot("com.example.app", appletest.NewSigner(t).Root).VerifyTransaction(jws); err == nil {
		t.Fatal("untrusted chain verified")
	}
	// The real Apple root rejects the fake chain.
	if _, err := billing.NewAppleVerifier("com.example.app").VerifyTransaction(jws); err == nil {
		t.Fatal("fake chain verified against Apple root")
	}
}

func TestAppleRootPinned(t *testing.T) {
	raw, err := os.ReadFile("AppleRootCA-G3.pem")
	if err != nil {
		t.Fatal(err)
	}
	block, _ := pem.Decode(raw)
	c, err := x509.ParseCertificate(block.Bytes)
	if err != nil || c.Subject.CommonName != "Apple Root CA - G3" {
		t.Fatalf("pinned root: %v %v", c, err)
	}
}
