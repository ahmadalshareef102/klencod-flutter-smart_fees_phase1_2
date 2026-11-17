import 'package:sqflite/sqflite.dart';

import '../../../core/database/audit_log.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/helpers/dates.dart';
import '../../installments/domain/installment_calculator.dart';

/// إنشاء خطط التقسيط للتسجيلات.
class FeePlanRepository {
  FeePlanRepository(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Database _db;
  final DateTime Function() _clock;

  /// خطة بأقساط متساوية في معاملة مستقلة. تعيد معرّف الخطة.
  Future<int> createEqualPlan({
    required int enrollmentId,
    required int count,
    required DateTime firstDue,
    required int intervalDays,
    int? actorId,
  }) {
    return _db.transaction((txn) => createPlanIn(
          txn,
          enrollmentId: enrollmentId,
          count: count,
          firstDue: firstDue,
          intervalDays: intervalDays,
          actorId: actorId,
        ));
  }

  /// نسخة تعمل داخل معاملة قائمة (تُستخدم عند تسجيل الطالب).
  /// - [periodMonths] غير null: استحقاقات شهرية (أو كل n شهر) بدل فاصل بالأيام.
  /// - [monthlyFee] غير null: خطة متكررة تُضاف أقساطها لاحقًا تلقائيًا.
  Future<int> createPlanIn(
    Transaction txn, {
    required int enrollmentId,
    required int count,
    required DateTime firstDue,
    required int intervalDays,
    int? periodMonths,
    int? monthlyFee,
    int? actorId,
  }) async {
    if (count <= 0) {
      throw const AppException('عدد الأقساط يجب أن يكون أكبر من صفر');
    }
    if (intervalDays <= 0) {
      throw const AppException('الفاصل بين الأقساط يجب أن يكون أكبر من صفر');
    }

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
    final dates = periodMonths != null
        ? List<DateTime>.generate(
            count, (i) => Dates.addMonths(firstDue, i * periodMonths))
        : InstallmentCalculator.dueDates(firstDue, count, intervalDays);
    final today = Dates.iso(_clock());

    final planId = await txn.insert('fee_plans', {
      'enrollment_id': enrollmentId,
      'installments_count': count,
      'first_due_date': Dates.iso(firstDue),
      'interval_days': intervalDays,
      'total_amount': total,
      'monthly_fee': monthlyFee,
    });

    for (var i = 0; i < count; i++) {
      final due = Dates.iso(dates[i]);
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
        'recurring': monthlyFee != null,
      },
      actorId: actorId,
    );
    return planId;
  }
}
