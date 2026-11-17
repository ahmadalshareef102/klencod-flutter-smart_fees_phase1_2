import 'package:sqflite/sqflite.dart';

import '../../../core/database/audit_log.dart';
import '../../../core/helpers/dates.dart';
import '../../batches/domain/batch_type.dart';

/// يُشغَّل عند فتح التطبيق وعند تحديث لوحة القيادة:
/// 1) يضيف قسط الفترة الجديدة (شهر/ربع/سنة) للدفعات المتكررة عند حلول موعدها.
/// 2) يحدّث حالات الأقساط (لم يحن/مستحق/متأخر) بحسب تاريخ اليوم.
class AccrualService {
  AccrualService(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Database _db;
  final DateTime Function() _clock;

  static const int _maxPeriodsPerRun = 600; // حماية من حلقة غير منتهية

  /// يعيد عدد الأقساط الجديدة المضافة.
  Future<int> run() async {
    final today = Dates.iso(_clock());

    return _db.transaction((txn) async {
      var created = 0;

      final plans = await txn.rawQuery('''
        SELECT fp.id AS plan_id, fp.enrollment_id, fp.monthly_fee,
               fp.first_due_date, b.batch_type, b.end_date,
               (SELECT MAX(seq) FROM installments i WHERE i.fee_plan_id = fp.id) AS last_seq
        FROM fee_plans fp
        JOIN enrollments e ON e.id = fp.enrollment_id
        JOIN batches b ON b.id = e.batch_id
        JOIN students s ON s.id = e.student_id
        WHERE fp.monthly_fee IS NOT NULL
          AND e.status = 'active'
          AND s.status = 'active' AND s.deleted_at IS NULL
          AND b.status = 'open' AND b.deleted_at IS NULL''');

      for (final p in plans) {
        final period =
            BatchType.fromCode(p['batch_type'] as String).periodMonths;
        if (period == null) continue;

        final fee = p['monthly_fee'] as int;
        final anchor = Dates.parse(p['first_due_date'] as String);
        final planId = p['plan_id'] as int;
        final enrollmentId = p['enrollment_id'] as int;
        var seq = (p['last_seq'] as int?) ?? 0;

        // لا تُحتسب فترات بعد تاريخ نهاية الدفعة.
        var limit = today;
        final end = p['end_date'] as String?;
        if (end != null && end.compareTo(limit) < 0) limit = end;

        var guard = 0;
        while (guard++ < _maxPeriodsPerRun) {
          final due = Dates.iso(Dates.addMonths(anchor, seq * period));
          if (due.compareTo(limit) > 0) break;
          seq++;
          await txn.insert('installments', {
            'fee_plan_id': planId,
            'enrollment_id': enrollmentId,
            'seq': seq,
            'amount': fee,
            'due_date': due,
            'paid_amount': 0,
            'status': 'not_due',
          });
          await txn.rawUpdate(
            'UPDATE enrollments SET original_fee = original_fee + ?, '
            'final_fee = final_fee + ?, '
            "updated_at = strftime('%Y-%m-%dT%H:%M:%SZ','now') WHERE id = ?",
            [fee, fee, enrollmentId],
          );
          await txn.rawUpdate(
            'UPDATE fee_plans SET total_amount = total_amount + ?, '
            'installments_count = installments_count + 1 WHERE id = ?',
            [fee, planId],
          );
          created++;
        }
      }

      // تحديث الحالات (التأخر يعتمد على تاريخ الاستحقاق).
      await txn.rawUpdate('''
        UPDATE installments SET status = CASE
          WHEN paid_amount >= amount THEN 'paid'
          WHEN due_date < ? THEN 'late'
          WHEN paid_amount > 0 THEN 'partial'
          WHEN due_date = ? THEN 'due'
          ELSE 'not_due' END''', [today, today]);

      if (created > 0) {
        await writeAudit(txn,
            entity: 'accrual',
            entityId: null,
            action: 'monthly_accrual',
            details: {'installments_created': created, 'date': today});
      }
      return created;
    });
  }
}
