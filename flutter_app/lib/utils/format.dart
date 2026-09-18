import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// ETB money formatting — "1,250.00 ETB" (PRD A10).
class Money {
  static final NumberFormat _fmt = NumberFormat.decimalPattern('en');
  static String etb(num amount, {bool withSymbol = true}) {
    final v = amount is int ? amount.toDouble() : amount;
    final s = _fmt.format(double.parse(v.toStringAsFixed(2)));
    return withSymbol ? '$s ETB' : s;
  }
}

/// Ethiopian phone helpers (+251 9XX XXX XXX, stored as 09XXXXXXXX).
class EthPhone {
  static String? normalize(String raw) {
    var d = raw.replaceAll(RegExp(r'[^0-9+]'), '').trim();
    if (d.startsWith('+251')) d = '0${d.substring(4)}';
    else if (d.startsWith('251')) d = '0${d.substring(3)}';
    if (RegExp(r'^09\d{8}$').hasMatch(d)) return d;
    return null;
  }

  static String pretty(String stored) {
    // 0911 234 567
    if (stored.length == 10) {
      return '${stored.substring(0, 4)} ${stored.substring(4, 7)} ${stored.substring(7)}';
    }
    return stored;
  }
}

/// Decimal text input — one dot, digits only (for qty / price fields).
class DecimalInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final t = newValue.text;
    if (t.isEmpty) return newValue;
    if (!RegExp(r'^\d*\.?\d{0,2}$').hasMatch(t)) return oldValue;
    return newValue;
  }
}

class IntInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final t = newValue.text;
    if (t.isEmpty) return newValue;
    if (!RegExp(r'^\d{1,6}$').hasMatch(t)) return oldValue;
    return newValue;
  }
}
