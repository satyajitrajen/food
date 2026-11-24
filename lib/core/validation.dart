/// Shared mobile-number validation (Indian format): exactly 10 digits, or
/// 12 digits starting with the 91 country code. Non-digits (spaces, dashes,
/// +91) are ignored. Returns null when valid, else a message.
String? validateMobile(String? v, {bool required = false}) {
  final raw = (v ?? '').trim();
  if (raw.isEmpty) {
    return required ? 'Mobile number is required' : null;
  }
  final clean = raw.replaceAll(RegExp(r'\D'), '');
  final tenDigit = clean.length == 10 && RegExp(r'^[6-9]').hasMatch(clean);
  final withCC = clean.length == 12 && clean.startsWith('91') && RegExp(r'^91[6-9]').hasMatch(clean);
  if (!(tenDigit || withCC)) {
    return 'Enter a valid 10-digit mobile number';
  }
  return null;
}

/// Delivery address limits; mirrored in backend/internal/api/text_input.go.
const int deliveryAddressMin = 5;
const int deliveryAddressMax = 300;

/// Collapses every whitespace run to one space and trims (same as server).
String cleanSingleLine(String s) => s.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).join(' ');

/// True for control chars, bidi overrides/isolates and the BOM. ZWJ/ZWNJ
/// (U+200C/U+200D) are allowed: Indic scripts need them.
bool hasHiddenChars(String s, {bool allowLineBreaks = false}) {
  for (final r in s.runes) {
    if (allowLineBreaks && (r == 0x09 || r == 0x0A || r == 0x0D)) continue;
    if (r < 0x20 || (r >= 0x7F && r <= 0x9F)) return true;
    if ((r >= 0x202A && r <= 0x202E) || (r >= 0x2066 && r <= 0x2069) || r == 0xFEFF) return true;
  }
  return false;
}

/// Required delivery address: [deliveryAddressMin]–[deliveryAddressMax]
/// code points after cleanup, no hidden characters.
String? validateDeliveryAddress(String? v) {
  final raw = v ?? '';
  // Check before cleanup: Dart's \s also matches U+FEFF, so cleaning first
  // would hide it (the server, which keeps it, would then refuse the order).
  if (hasHiddenChars(raw, allowLineBreaks: true)) return 'Address contains hidden or invalid characters';
  final clean = cleanSingleLine(raw);
  if (clean.isEmpty) return 'Enter the delivery address';
  final n = clean.runes.length;
  if (n < deliveryAddressMin) return 'Use at least $deliveryAddressMin characters';
  if (n > deliveryAddressMax) return 'Use at most $deliveryAddressMax characters';
  return null;
}
