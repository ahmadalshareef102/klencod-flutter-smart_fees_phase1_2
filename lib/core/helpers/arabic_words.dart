/// كتابة المبلغ بالحروف العربية (للسندات). يدعم حتى 999,999,999,999.
class ArabicWords {
  ArabicWords._();

  static const List<String> _ones = [
    '', 'واحد', 'اثنان', 'ثلاثة', 'أربعة', 'خمسة', 'ستة', 'سبعة', 'ثمانية',
    'تسعة', 'عشرة', 'أحد عشر', 'اثنا عشر', 'ثلاثة عشر', 'أربعة عشر',
    'خمسة عشر', 'ستة عشر', 'سبعة عشر', 'ثمانية عشر', 'تسعة عشر',
  ];
  static const List<String> _tens = [
    '', '', 'عشرون', 'ثلاثون', 'أربعون', 'خمسون', 'ستون', 'سبعون', 'ثمانون',
    'تسعون',
  ];
  static const List<String> _hundreds = [
    '', 'مائة', 'مائتان', 'ثلاثمائة', 'أربعمائة', 'خمسمائة', 'ستمائة',
    'سبعمائة', 'ثمانمائة', 'تسعمائة',
  ];

  /// مجموعة من 1 إلى 999. [beforeScale] لصيغة الإضافة: «مائتا ألف».
  static String _group(int n, {bool beforeScale = false}) {
    final parts = <String>[];
    final h = n ~/ 100;
    final r = n % 100;
    if (h > 0) {
      parts.add(h == 2 && r == 0 && beforeScale ? 'مائتا' : _hundreds[h]);
    }
    if (r > 0) {
      if (r < 20) {
        parts.add(_ones[r]);
      } else {
        final t = r ~/ 10;
        final o = r % 10;
        parts.add(o == 0 ? _tens[t] : '${_ones[o]} و${_tens[t]}');
      }
    }
    return parts.join(' و');
  }

  static String _scaled(int n, String single, String dual, String plural) {
    if (n == 1) return single;
    if (n == 2) return dual;
    if (n <= 10) return '${_group(n)} $plural';
    return '${_group(n, beforeScale: true)} $single';
  }

  static String convert(int value) {
    if (value < 0 || value > 999999999999) {
      throw ArgumentError('المبلغ خارج النطاق المدعوم');
    }
    if (value == 0) return 'صفر';
    final billions = value ~/ 1000000000;
    final millions = (value ~/ 1000000) % 1000;
    final thousands = (value ~/ 1000) % 1000;
    final rest = value % 1000;
    final parts = <String>[];
    if (billions > 0) parts.add(_scaled(billions, 'مليار', 'ملياران', 'مليارات'));
    if (millions > 0) parts.add(_scaled(millions, 'مليون', 'مليونان', 'ملايين'));
    if (thousands > 0) parts.add(_scaled(thousands, 'ألف', 'ألفان', 'آلاف'));
    if (rest > 0) parts.add(_group(rest));
    return parts.join(' و');
  }

  /// صيغة السند: «خمسون ألف ريال يمني فقط لا غير».
  static String yemeniRial(int value) =>
      '${convert(value)} ريال يمني فقط لا غير';
}
