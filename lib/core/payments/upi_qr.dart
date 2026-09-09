// UPI QR helpers for customer food payments.
//
// The settings screen stores a UPI ID (`name@bank`) — the preferred way —
// and the POS renders a per-bill QR with the amount + payee pre-filled.
// An optional uploaded image override is supported for bank-branded QRs.

String? validateUpiId(String input) {
  final id = input.trim();
  if (id.isEmpty) return null;
  final ok = RegExp(r'^[A-Za-z0-9.\-_]{2,}@[A-Za-z]{2,}$').hasMatch(id);
  return ok ? id : null;
}

/// Builds a `upi://pay?...` string for QR encoding.
String buildUpiUri(
  String upiId, {
  String? payeeName,
  double? amount,
  String? note,
}) {
  final params = <String, String>{'pa': upiId.trim()};
  if (payeeName != null && payeeName.trim().isNotEmpty) {
    params['pn'] = payeeName.trim();
  }
  if (amount != null && amount > 0) {
    params['am'] = amount.toStringAsFixed(2);
    params['cu'] = 'INR';
  }
  if (note != null && note.trim().isNotEmpty) {
    params['tn'] = note.trim();
  }
  return Uri(scheme: 'upi', host: 'pay', queryParameters: params).toString();
}
