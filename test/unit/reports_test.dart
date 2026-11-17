import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fees/core/database/app_database.dart';
import 'package:smart_fees/core/helpers/date_range.dart';
import 'package:smart_fees/features/attendance/data/attendance_repository.dart';
import 'package:smart_fees/features/expenses/data/expense_repository.dart';
import 'package:smart_fees/features/fees/data/fee_plan_repository.dart';
import 'package:smart_fees/features/institute/data/institute_repository.dart';
import 'package:smart_fees/features/payments/data/payment_repository.dart';
import 'package:smart_fees/features/receipts/data/receipt_repository.dart';
import 'package:smart_fees/features/reports/data/report_repository.dart';

import '../helpers/test_db.dart';

void main() {
  late AppDatabase appDb;
  late PaymentRepository pay;
  late ReportRepository reports;
  final now = DateTime(2026, 11, 16);

  setUp(() async {
    appDb = await openTestDb();
    pay = PaymentRepository(appDb.db, clock: () => now);
    reports = ReportRepository(appDb.db, AttendanceRepository(appDb.db),
        clock: () => now);
  });
  tearDown(() async => appDb.close());

  Future<int> pays(int enr, int amount) async => (await pay.recordPayment(
          enrollmentId: enr,
          amount: amount,
          paidAt: '2026-11-16',
          method: PaymentMethod.cash))
      .paymentId;

  test('التحصيل: الدفعة الملغاة لا تدخل في الإجمالي', () async {
    final enr = await seedEnrollment(appDb.db, originalFee: 50000);
    await pays(enr, 20000);
    final p2 = await pays(enr, 5000);
    await pay.reversePayment(paymentId: p2, reason: 'خطأ');
    final r = await reports.collections(DateRange.today(now));
    expect(r.rows.length, 1);
    expect(r.rows.first.last, 20000);
  });

  test('غير الدافعين والجزئي', () async {
    final a = await seedEnrollment(appDb.db, originalFee: 10000);
    final b = await seedEnrollment(appDb.db, originalFee: 10000);
    await pays(b, 4000);
    expect((await reports.unpaidStudents()).rows.length, 1);
    final partial = await reports.partialStudents();
    expect(partial.rows.single.last, 6000);
    expect(a, isNot(b));
  });

  test('صافي التدفق = التحصيل − المصروفات', () async {
    final enr = await seedEnrollment(appDb.db, originalFee: 50000);
    await pays(enr, 30000);
    final ex = ExpenseRepository(appDb.db);
    await ex.add(ExpenseInput(
        categoryId: (await ex.categories()).first.id,
        amount: 12000,
        spentAt: '2026-11-16',
        method: PaymentMethod.cash));
    final r = await reports.netCashFlow(DateRange.today(now));
    expect(r.rows[2].last, 18000);
  });

  test('كشف حساب الطالب: الرصيد التراكمي', () async {
    final enr = await seedEnrollment(appDb.db, originalFee: 10000);
    await FeePlanRepository(appDb.db, clock: () => now).createEqualPlan(
        enrollmentId: enr,
        count: 1,
        firstDue: DateTime(2026, 11, 10),
        intervalDays: 30);
    await pays(enr, 4000);
    final sid = (await appDb.db.query('enrollments',
            where: 'id = ?', whereArgs: [enr]))
        .first['student_id'] as int;
    final r = await reports.studentStatement(sid);
    expect(r.rows.last.last, 6000);
    expect(r.rows.first[2], 10000);
  });

  test('بيانات السند تحمل التفقيط والمتبقي', () async {
    final enr = await seedEnrollment(appDb.db, originalFee: 50000);
    final id = await pays(enr, 20000);
    final d = await ReceiptRepository(appDb.db, InstituteRepository(appDb.db))
        .load(id);
    expect(d.remaining, 30000);
    expect(d.amountWords, contains('عشرون ألف'));
    expect(d.cancelled, false);
  });
}
