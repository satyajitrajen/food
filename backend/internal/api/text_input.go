package api

import "strings"

// Delivery address limits; mirrored in lib/core/validation.dart.
const (
	deliveryAddressMin = 5
	deliveryAddressMax = 300
)

// cleanSingleLine collapses every whitespace run to one space and trims.
func cleanSingleLine(s string) string {
	return strings.Join(strings.Fields(s), " ")
}

// hasHiddenChars reports control characters, bidi overrides/isolates and the
// byte-order mark, which make stored text display differently from what it
// says. ZWJ/ZWNJ (U+200C/U+200D) stay allowed: Indic scripts need them.
func hasHiddenChars(s string, allowLineBreaks bool) bool {
	for _, r := range s {
		if allowLineBreaks && (r == '\t' || r == '\n' || r == '\r') {
			continue
		}
		switch {
		case r < 0x20, r >= 0x7F && r <= 0x9F:
			return true
		case r >= 0x202A && r <= 0x202E, r >= 0x2066 && r <= 0x2069, r == 0xFEFF:
			return true
		case r == 0xFFFD: // invalid UTF-8 decodes to the replacement char
			return true
		}
	}
	return false
}
