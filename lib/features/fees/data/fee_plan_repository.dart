import 'package:sqflite/sqflite.dart';

import '../../../core/database/audit_log.dart';
import '../../../core/errors/app_exception.dart';
import '../../installments/domain/installment_calculator.dart';

/// إنشاء خطط التقسيط للتسجيلات.
class FeePlanRepository {
  FeePlanRepository(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Database _db;
  final DateTime Function() _clock;

  /// ينشئ خطة بأقساط متساوية (الباقي يوزّع بدقة) إجماليها = الرسوم النهائية
  /// للتسجيل. تُنفَّذ في معاملة واحدة. تعيد معرّف الخطة.
  Future<int> createEqualPlan({
    required int enrollmentId,
    required int count,
    required DateTime firstDue,
    required int intervalDays,
    int? actorId,
  }) async {
    if (count <= 0) throw const AppException('عدد الأقساط يجب أن يكون أكبر من صفر');
    if (intervalDays <= 0) {
      throw const AppException('الفاصل بين الأقساط يجب أن يكون أكبر من صفر');
    }

    return _db.transaction((txn) async {
      final enr = await txn.query(
        'enrollments',
        columns: ['final_fee'],
        where: 'id = ?',
        whereArgs: [enrollmentId],
        limit: 1,
      );
      if (enr.isEmpty) throw const AppException('التسجيل غير موجود');
      final total = enr.first['final_fee'] as int;
      if (total < count) {
        throw const AppException('الرسوم أقل من عدد الأقساط المطلوب');
      }
      final existing = await txn.query(
        'fee_plans',
        where: 'enrollment_id = ?',
        whereArgs: [enrollmentId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        throw const AppException('لهذا التسجيل خطة تقسيط موجودة مسبقًا');
      }

      final amounts = InstallmentCalculator.splitAmount(total, count);
      final dates = InstallmentCalculator.dueDates(firstDue, count, intervalDays);
      final today = InstallmentCalculator.formatDate(_clock());

      final planId = await txn.insert('fee_plans', {
        'enrollment_id': enrollmentId,
        'installments_count': count,
        'first_due_date': InstallmentCalculator.formatDate(firstDue),
        'interval_days': intervalDays,
        'total_amount': total,
      });

      for (var i = 0; i < count; i++) {
        final due = InstallmentCalculator.formatDate(dates[i]);
        await txn.insert('installments', {
          'fee_plan_id': planId,
          'enrollment_id': enrollmentId,
          'seq': i + 1,
          'amount': amounts[i],
          'due_date': due,
          'paid_amount': 0,
          'status': InstallmentCalculator.statusFor(
            amount: amounts[i],
            paid: 0,
            dueDate: due,
            today: today,
          ).code,
        });
      }

      await writeAudit(
        txn,
        entity: 'fee_plan',
        entityId: planId,
        action: 'create',
        details: {
          'enrollment_id': enrollmentId,
          'count': count,
          'total': total,
        },
        actorId: actorId,
      );
      return planId;
    });
  }
}
