package billing

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"testing"
	"time"

	"foodpos/backend/internal/models"
)

func TestRenderInvoicePDF(t *testing.T) {
	now := time.Now()
	inv := models.SaaSInvoice{
		InvoiceNo: "SAAS-INV-1", OrgID: "org-x", AmountPaise: 149900,
		GSTPercent: 18, TaxPaise: 26982, GrossPaise: 176882,
		Method: "bank", PaidAt: now, PeriodStart: &now, PeriodEnd: &now,
	}
	org := models.Organization{Name: "Test Foods", Email: "a@b.c", GSTIN: "27XXXX"}
	var buf bytes.Buffer
	if err := RenderInvoicePDF(&buf, org, inv); err != nil {
		t.Fatal(err)
	}
	out := buf.String()
	if len(out) < 500 || out[:5] != "%PDF-" {
		t.Fatalf("output does not look like a PDF (len=%d head=%q)", len(out), out[:min(12, len(out))])
	}
}

func TestRazorpaySignatureVerify(t *testing.T) {
	gw := &RazorpayGateway{key: "k", secret: "s", webhookSecret: "wh-secret", http: nil}
	payload := []byte(`{"event":"payment.captured"}`)
	mac := hmac.New(sha256.New, []byte("wh-secret"))
	_, _ = mac.Write(payload)
	sig := hex.EncodeToString(mac.Sum(nil))
	if !gw.VerifySignature(payload, sig) {
		t.Fatal("valid signature rejected")
	}
	if gw.VerifySignature(payload, sig+"00") {
		t.Fatal("invalid signature accepted")
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
