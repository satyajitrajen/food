package license

// Signed offline entitlements: the server signs {org, status, valid_until,
// grace_days} with an HMAC so POS terminals can verify offline without
// trusting their own clock beyond the signature. Tokens are opaque strings:
//
//	base64url(payloadJSON).base64url(hmacSHA256(secret, payloadJSON))

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"strings"

	"foodpos/backend/internal/models"
)

func secret(licenseSecret, jwtSecret string) []byte {
	if licenseSecret != "" {
		return []byte(licenseSecret)
	}
	return []byte(jwtSecret) // fallback keeps single-secret deployments simple
}

// Sign returns an opaque entitlement token for the payload.
func Sign(p models.Entitlement, licenseSecret, jwtSecret string) (string, error) {
	payload, err := json.Marshal(p)
	if err != nil {
		return "", err
	}
	body := base64.RawURLEncoding.EncodeToString(payload)
	mac := hmac.New(sha256.New, secret(licenseSecret, jwtSecret))
	_, _ = mac.Write(payload)
	sig := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	return body + "." + sig, nil
}

// Verify checks the token signature and returns the payload. ok=false on any
// tamper/format error.
func Verify(token, licenseSecret, jwtSecret string) (models.Entitlement, bool) {
	parts := strings.Split(token, ".")
	if len(parts) != 2 {
		return models.Entitlement{}, false
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return models.Entitlement{}, false
	}
	mac := hmac.New(sha256.New, secret(licenseSecret, jwtSecret))
	_, _ = mac.Write(payload)
	want, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil || !hmac.Equal(want, mac.Sum(nil)) {
		return models.Entitlement{}, false
	}
	var e models.Entitlement
	if err := json.Unmarshal(payload, &e); err != nil {
		return models.Entitlement{}, false
	}
	return e, true
}
