import 'package:intl/intl.dart';

import '../constants/app_constants.dart';

/// كل المبالغ في التطبيق أعداد صحيحة بوحدة الريال اليمني (بدون floating point).
class Money {
  Money._();

  static final NumberFormat _fmt = NumberFormat('#,##0', 'en');

  /// أرقام بفواصل آلاف دون رمز العملة.
  static String group(int amount) => _fmt.format(amount);

  static String format(int amount) =>
      '${_fmt.format(amount)} ${AppConstants.currencySymbol}';

  /// يحوّل نصًا مُدخلًا (أرقام عربية أو لاتينية، مع فواصل آلاف) إلى عدد صحيح.
  /// يعيد null إذا كان النص فارغًا أو سالبًا أو يحتوي كسورًا أو رموزًا غير رقمية.
  static int? parse(String input) {
    final normalized = _normalizeDigits(input)
        .replaceAll(RegExp(r'[,٬،\s]'), '');
    if (normalized.isEmpty || !RegExp(r'^\d+$').hasMatch(normalized)) {
      return null;
    }
    return int.tryParse(normalized);
  }

  static String _normalizeDigits(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      if (r >= 0x0660 && r <= 0x0669) {
        b.writeCharCode(r - 0x0660 + 0x30);
      } else if (r >= 0x06F0 && r <= 0x06F9) {
        b.writeCharCode(r - 0x06F0 + 0x30);
      } else {
        b.writeCharCode(r);
      }
    }
    return b.toString();
  }
}
