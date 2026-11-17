/// أدوات التواريخ. التواريخ تُخزَّن نصًا بصيغة yyyy-MM-dd.
class Dates {
  Dates._();

  static String iso(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-$m-$day';
  }

  static DateTime parse(String s) {
    final p = s.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  /// إضافة أشهر مع تثبيت اليوم عند آخر يوم في الشهر عند الحاجة (31 -> 28/30).
  static DateTime addMonths(DateTime d, int n) {
    final total = d.month - 1 + n;
    final y = d.year + total ~/ 12;
    final m = total % 12 + 1;
    final last = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, d.day > last ? last : d.day);
  }

  /// عدد الأشهر التقريبي بين تاريخين (30 يومًا = شهر)، بحد أدنى 1.
  static int approxMonths(DateTime a, DateTime b) {
    final months = (b.difference(a).inDays / 30).round();
    return months < 1 ? 1 : months;
  }
}
