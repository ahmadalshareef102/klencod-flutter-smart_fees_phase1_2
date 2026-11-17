import 'dates.dart';

/// فترة زمنية بتواريخ yyyy-MM-dd (شاملة الطرفين).
class DateRange {
  const DateRange(this.from, this.to);

  final String from;
  final String to;

  /// كل الفترات.
  static const DateRange all = DateRange('0000-01-01', '9999-12-31');

  factory DateRange.today(DateTime now) {
    final d = Dates.iso(now);
    return DateRange(d, d);
  }

  factory DateRange.month(DateTime now) => DateRange(
        Dates.iso(DateTime(now.year, now.month, 1)),
        Dates.iso(DateTime(now.year, now.month + 1, 0)),
      );

  bool get isAll => this == all;

  String get label => isAll
      ? 'كل الفترات'
      : (from == to ? from : 'من $from إلى $to');

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}
