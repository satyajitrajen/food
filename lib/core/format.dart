import 'package:intl/intl.dart';

final NumberFormat _inr2 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
final NumberFormat _inr0 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// Rupees with Indian digit grouping: ₹1,25,000 · ₹49.50. Paise are shown
/// only when present, so whole amounts stay compact. [whole] forces rounding
/// for big KPI tiles.
String formatInr(num amount, {bool whole = false}) {
  var v = amount.toDouble();
  // -0.0 (e.g. "change to return" on exact cash) would render as "-₹0".
  if ((v * 100).round() == 0) v = 0;
  if (whole) return _inr0.format(v.round());
  final hasPaise = ((v * 100).round() % 100) != 0;
  return hasPaise ? _inr2.format(v) : _inr0.format(v);
}

/// Editable rupee text for inputs: '49.5' → '49.50', '50.0' → '50'.
String rupeeInput(double amount) {
  final cents = (amount * 100).round();
  return cents % 100 == 0 ? (cents ~/ 100).toString() : (cents / 100).toStringAsFixed(2);
}

/// Counted label: plural(1, 'item') → '1 item', plural(3, 'entry',
/// 'entries') → '3 entries'. Returns the full string including the count,
/// so templates embed it whole.
String plural(int count, String singular, [String? pluralWord]) =>
    '$count ${count == 1 ? singular : (pluralWord ?? '${singular}s')}';

final DateFormat _date = DateFormat('d MMM yyyy');
final DateFormat _dateTime = DateFormat('d MMM yyyy, h:mm a');
final DateFormat _time = DateFormat('h:mm a');

String formatDate(DateTime d) => _date.format(d.toLocal());
String formatDateTime(DateTime d) => _dateTime.format(d.toLocal());
String formatTime(DateTime d) => _time.format(d.toLocal());
