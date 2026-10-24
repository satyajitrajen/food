package billing

// Apple App Store in-app subscriptions (StoreKit 2). Apple signs every
// transaction and server notification as a JWS whose x5c header carries the
// signing chain up to Apple Root CA - G3. Verification is fully offline: check
// the chain against the pinned root, then the ES256 signature with the leaf
// key. No App Store Server API key is needed for this.

import (
	"crypto/ecdsa"
	"crypto/sha256"
	"crypto/x509"
	_ "embed"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"math/big"
	"strings"
	"time"
)

//go:embed AppleRootCA-G3.pem
var appleRootPEM []byte

// Apple's marker OIDs: the intermediate (WWDR G6) and the App Store signing leaf.
var (
	oidAppleIntermediate = []int{1, 2, 840, 113635, 100, 6, 2, 1}
	oidAppleLeaf         = []int{1, 2, 840, 113635, 100, 6, 11, 1}
)

var ErrAppleJWS = errors.New("invalid Apple signed payload")

// AppleTransaction is the decoded JWSTransactionDecodedPayload subset we use.
type AppleTransaction struct {
	TransactionID         string `json:"transactionId"`
	OriginalTransactionID string `json:"originalTransactionId"`
	BundleID              string `json:"bundleId"`
	ProductID             string `json:"productId"`
	PurchaseDate          int64  `json:"purchaseDate"`
	ExpiresDate           int64  `json:"expiresDate"`
	RevocationDate        int64  `json:"revocationDate"`
	Type                  string `json:"type"`
	Environment           string `json:"environment"`
	AppAccountToken       string `json:"appAccountToken"`
	Price                 int64  `json:"price"` // milli-units of Currency
	Currency              string `json:"currency"`
	OfferType             int    `json:"offerType"`
}

// Expires is the end of the period this transaction pays for.
func (t *AppleTransaction) Expires() time.Time { return time.UnixMilli(t.ExpiresDate) }

// PricePaise converts Apple's milli-unit price to paise (0 when not INR).
func (t *AppleTransaction) PricePaise() int64 {
	if t.Currency != "INR" {
		return 0
	}
	return t.Price / 10
}

// AppleRenewalInfo is the decoded JWSRenewalInfoDecodedPayload subset we use.
type AppleRenewalInfo struct {
	OriginalTransactionID string `json:"originalTransactionId"`
	AutoRenewStatus       int    `json:"autoRenewStatus"`
	ProductID             string `json:"productId"`
}

// AppleNotification is the decoded App Store Server Notification V2 payload.
type AppleNotification struct {
	NotificationType string `json:"notificationType"`
	Subtype          string `json:"subtype"`
	NotificationUUID string `json:"notificationUUID"`
	Data             struct {
		BundleID              string `json:"bundleId"`
		Environment           string `json:"environment"`
		SignedTransactionInfo string `json:"signedTransactionInfo"`
		SignedRenewalInfo     string `json:"signedRenewalInfo"`
	} `json:"data"`
}

// AppleVerifier checks Apple-signed JWS payloads for one app.
type AppleVerifier struct {
	BundleID string
	roots    *x509.CertPool
	now      func() time.Time
}

func NewAppleVerifier(bundleID string) *AppleVerifier {
	block, _ := pem.Decode(appleRootPEM)
	root, _ := x509.ParseCertificate(block.Bytes)
	return NewAppleVerifierWithRoot(bundleID, root)
}

// NewAppleVerifierWithRoot trusts a different root (tests).
func NewAppleVerifierWithRoot(bundleID string, root *x509.Certificate) *AppleVerifier {
	roots := x509.NewCertPool()
	if root != nil {
		roots.AddCert(root)
	}
	return &AppleVerifier{BundleID: bundleID, roots: roots, now: time.Now}
}

// VerifyTransaction verifies a signed transaction and checks it belongs to
// this app.
func (v *AppleVerifier) VerifyTransaction(jws string) (*AppleTransaction, error) {
	var tx AppleTransaction
	if err := v.verify(jws, &tx); err != nil {
		return nil, err
	}
	if tx.BundleID != v.BundleID {
		return nil, fmt.Errorf("%w: bundle %q", ErrAppleJWS, tx.BundleID)
	}
	return &tx, nil
}

// VerifyRenewalInfo verifies signed renewal info.
func (v *AppleVerifier) VerifyRenewalInfo(jws string) (*AppleRenewalInfo, error) {
	var ri AppleRenewalInfo
	if err := v.verify(jws, &ri); err != nil {
		return nil, err
	}
	return &ri, nil
}

// VerifyNotification verifies a V2 server notification's signedPayload.
func (v *AppleVerifier) VerifyNotification(jws string) (*AppleNotification, error) {
	var n AppleNotification
	if err := v.verify(jws, &n); err != nil {
		return nil, err
	}
	if n.Data.BundleID != v.BundleID {
		return nil, fmt.Errorf("%w: bundle %q", ErrAppleJWS, n.Data.BundleID)
	}
	return &n, nil
}

func (v *AppleVerifier) verify(jws string, out any) error {
	parts := strings.Split(jws, ".")
	if len(parts) != 3 {
		return ErrAppleJWS
	}
	rawHeader, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return ErrAppleJWS
	}
	var header struct {
		Alg string   `json:"alg"`
		X5c []string `json:"x5c"`
	}
	if err := json.Unmarshal(rawHeader, &header); err != nil || header.Alg != "ES256" || len(header.X5c) < 2 {
		return ErrAppleJWS
	}
	certs := make([]*x509.Certificate, len(header.X5c))
	for i, c := range header.X5c {
		der, err := base64.StdEncoding.DecodeString(c)
		if err != nil {
			return ErrAppleJWS
		}
		if certs[i], err = x509.ParseCertificate(der); err != nil {
			return ErrAppleJWS
		}
	}
	leaf := certs[0]
	inter := x509.NewCertPool()
	for _, c := range certs[1:] {
		inter.AddCert(c)
	}
	if _, err := leaf.Verify(x509.VerifyOptions{
		Roots: v.roots, Intermediates: inter, CurrentTime: v.now(),
		KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageAny},
	}); err != nil {
		return fmt.Errorf("%w: chain: %v", ErrAppleJWS, err)
	}
	if !hasExt(leaf, oidAppleLeaf) || !hasExt(certs[1], oidAppleIntermediate) {
		return fmt.Errorf("%w: not an App Store signing chain", ErrAppleJWS)
	}
	pub, ok := leaf.PublicKey.(*ecdsa.PublicKey)
	if !ok {
		return ErrAppleJWS
	}
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil || len(sig) != 64 {
		return ErrAppleJWS
	}
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	r, s := new(big.Int).SetBytes(sig[:32]), new(big.Int).SetBytes(sig[32:])
	if !ecdsa.Verify(pub, digest[:], r, s) {
		return fmt.Errorf("%w: signature", ErrAppleJWS)
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return ErrAppleJWS
	}
	return json.Unmarshal(payload, out)
}

func hasExt(c *x509.Certificate, oid []int) bool {
	for _, e := range c.Extensions {
		if e.Id.Equal(oid) {
			return true
		}
	}
	return false
}
