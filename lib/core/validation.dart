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
