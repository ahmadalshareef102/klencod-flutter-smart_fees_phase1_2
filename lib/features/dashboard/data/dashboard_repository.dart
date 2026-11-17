import 'package:sqflite/sqflite.dart';

import '../../../core/helpers/dates.dart';

class DashboardStats {
  const DashboardStats({
    required this.batches,
    required this.students,
    required this.recentStudents,
    required this.lateStudents,
    required this.totalFees,
    required this.collected,
    required this.collectedToday,
    required this.expensesToday,
  });

  final int batches;
  final int students;
  final int recentStudents;
  final int lateStudents;
  final int totalFees;
  final int collected;
  final int collectedToday;
  final int expensesToday;

  int get remaining => totalFees - collected;

  /// نسبة المحصَّل من إجمالي الرسوم (0..1).
  double get collectedRatio =>
      totalFees <= 0 ? 0 : (collected / totalFees).clamp(0.0, 1.0);
}

/// أرقام لوحة القيادة، كلها محسوبة من قاعدة البيانات.
class DashboardRepository {
  DashboardRepository(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Database _db;
  final DateTime Function() _clock;

  Future<int> _int(String sql, [List<Object?> args = const []]) async {
    final r = await _db.rawQuery(sql, args);
    return (r.first.values.first as num?)?.toInt() ?? 0;
  }

  Future<DashboardStats> load() async {
    final now = _clock();
    final today = Dates.iso(now);
    final since = Dates.iso(now.subtract(const Duration(days: 30)));

    return DashboardStats(
      batches: await _int(
          "SELECT COUNT(*) FROM batches WHERE deleted_at IS NULL AND status != 'archived'"),
      students:
          await _int('SELECT COUNT(*) FROM students WHERE deleted_at IS NULL'),
      recentStudents: await _int(
          'SELECT COUNT(*) FROM students WHERE deleted_at IS NULL AND registered_at >= ?',
          [since]),
      lateStudents: await _int('''
        SELECT COUNT(DISTINCT e.student_id) FROM installments i
          JOIN enrollments e ON e.id = i.enrollment_id
          JOIN students s ON s.id = e.student_id
         WHERE s.deleted_at IS NULL AND e.status = 'active'
           AND i.paid_amount < i.amount AND i.due_date < ?''', [today]),
      totalFees: await _int('''
        SELECT COALESCE(SUM(e.final_fee), 0) FROM enrollments e
          JOIN students s ON s.id = e.student_id
         WHERE s.deleted_at IS NULL AND e.status != 'cancelled' '''),
      collected: await _int('''
        SELECT COALESCE(SUM(p.amount), 0) FROM payments p
          JOIN enrollments e ON e.id = p.enrollment_id
          JOIN students s ON s.id = e.student_id
         WHERE p.status = 'active' AND s.deleted_at IS NULL'''),
      collectedToday: await _int(
          "SELECT COALESCE(SUM(amount), 0) FROM payments WHERE status = 'active' AND paid_at = ?",
          [today]),
      expensesToday: await _int(
          'SELECT COALESCE(SUM(amount), 0) FROM expenses WHERE deleted_at IS NULL AND spent_at = ?',
          [today]),
    );
  }
}
