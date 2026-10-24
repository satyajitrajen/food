// Package appletest builds a fake Apple App Store signing chain (root,
// intermediate and leaf carrying Apple's marker OIDs) and signs JWS payloads
// with it, so StoreKit verification can be tested end to end.
package appletest

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/json"
	"math/big"
	"testing"
	"time"
)

type Signer struct {
	Root    *x509.Certificate
	chain   []*x509.Certificate
	leafKey *ecdsa.PrivateKey
}

func NewSigner(t *testing.T) *Signer {
	t.Helper()
	rootKey := mustKey(t)
	interKey := mustKey(t)
	leafKey := mustKey(t)
	root := mustCert(t, "Fake Apple Root", nil, rootKey, nil, rootKey, true)
	inter := mustCert(t, "Fake WWDR", []int{1, 2, 840, 113635, 100, 6, 2, 1}, interKey, root, rootKey, true)
	leaf := mustCert(t, "Fake App Store", []int{1, 2, 840, 113635, 100, 6, 11, 1}, leafKey, inter, interKey, false)
	return &Signer{Root: root, chain: []*x509.Certificate{leaf, inter, root}, leafKey: leafKey}
}

// Sign returns a compact ES256 JWS of payload with the x5c chain header.
func (s *Signer) Sign(t *testing.T, payload any) string {
	t.Helper()
	x5c := make([]string, len(s.chain))
	for i, c := range s.chain {
		x5c[i] = base64.StdEncoding.EncodeToString(c.Raw)
	}
	h, _ := json.Marshal(map[string]any{"alg": "ES256", "x5c": x5c})
	p, err := json.Marshal(payload)
	if err != nil {
		t.Fatal(err)
	}
	input := base64.RawURLEncoding.EncodeToString(h) + "." + base64.RawURLEncoding.EncodeToString(p)
	digest := sha256.Sum256([]byte(input))
	r, sv, err := ecdsa.Sign(rand.Reader, s.leafKey, digest[:])
	if err != nil {
		t.Fatal(err)
	}
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	sv.FillBytes(sig[32:])
	return input + "." + base64.RawURLEncoding.EncodeToString(sig)
}

func mustKey(t *testing.T) *ecdsa.PrivateKey {
	k, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	return k
}

func mustCert(t *testing.T, cn string, oid []int, key *ecdsa.PrivateKey, parent *x509.Certificate, parentKey *ecdsa.PrivateKey, ca bool) *x509.Certificate {
	t.Helper()
	tmpl := &x509.Certificate{
		SerialNumber:          big.NewInt(time.Now().UnixNano()),
		Subject:               pkix.Name{CommonName: cn},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(24 * time.Hour),
		IsCA:                  ca,
		BasicConstraintsValid: true,
		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign,
	}
	if oid != nil {
		tmpl.ExtraExtensions = []pkix.Extension{{Id: oid, Value: []byte{0x05, 0x00}}}
	}
	if parent == nil {
		parent = tmpl
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, parent, &key.PublicKey, parentKey)
	if err != nil {
		t.Fatal(err)
	}
	c, err := x509.ParseCertificate(der)
	if err != nil {
		t.Fatal(err)
	}
	return c
}
