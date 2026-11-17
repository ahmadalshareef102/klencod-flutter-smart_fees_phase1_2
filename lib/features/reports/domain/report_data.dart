import '../../../core/helpers/money.dart';

/// تقرير جاهز للعرض والتصدير. الخلايا: int (أعداد/مبالغ) أو String.
class ReportData {
  const ReportData({
    required this.title,
    this.subtitle,
    required this.columns,
    required this.rows,
    this.summary = const [],
  });

  final String title;
  final String? subtitle;
  final List<String> columns;
  final List<List<Object>> rows;

  /// ملخص يُعرض تحت الجدول (إجماليات…).
  final List<MapEntry<String, String>> summary;

  /// نص الخلية للعرض والـ PDF: الأعداد بفواصل آلاف.
  static String cellText(Object v) => v is int ? Money.group(v) : '$v';

  /// نسخة صفوفها تحتوي النص [q] (للبحث والتصفية قبل الطباعة/التصدير).
  ReportData filtered(String q) {
    final needle = q.trim();
    if (needle.isEmpty) return this;
    return ReportData(
      title: title,
      subtitle: subtitle,
      columns: columns,
      summary: summary,
      rows: rows
          .where((r) => r.any((c) => cellText(c).contains(needle)))
          .toList(),
    );
  }
}
