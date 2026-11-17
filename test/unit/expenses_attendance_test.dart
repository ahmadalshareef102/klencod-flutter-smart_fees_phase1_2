import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fees/core/database/app_database.dart';
import 'package:smart_fees/core/errors/app_exception.dart';
import 'package:smart_fees/core/helpers/date_range.dart';
import 'package:smart_fees/features/attendance/data/attendance_repository.dart';
import 'package:smart_fees/features/dashboard/data/dashboard_repository.dart';
import 'package:smart_fees/features/expenses/data/expense_repository.dart';
import 'package:smart_fees/features/payments/data/payment_repository.dart';

import '../helpers/test_db.dart';

void main() {
  late AppDatabase appDb;
  final now = DateTime(2026, 11, 16);

  setUp(() async => appDb = await openTestDb());
  tearDown(() async => appDb.close());

  group('المصروفات', () {
    test('إضافة مصروف وإلغاؤه (حذف ناعم) ويظهر في الملخص', () async {
      final repo = ExpenseRepository(appDb.db);
      final cats = await repo.categories();
      expect(cats, isNotEmpty);
      final id = await repo.add(ExpenseInput(
          categoryId: cats.first.id,
          amount: 7000,
          spentAt: '2026-11-16',
          method: PaymentMethod.cash));
      var s = await repo.summary(DateRange.today(now));
      expect(s.total, 7000);
      await repo.cancel(id, reason: 'خطأ إدخال');
      s = await repo.summary(DateRange.today(now));
      expect(s.total, 0);
      final raw = await appDb.db.query('expenses');
      expect(raw.length, 1); // لم يُحذف فعليًا
    });

    test('رفض المبلغ الصفري والتاريخ غير الصالح', () async {
      final repo = ExpenseRepository(appDb.db);
      final c = (await repo.categories()).first.id;
      expect(
          () => repo.add(ExpenseInput(
              categoryId: c,
              amount: 0,
              spentAt: '2026-11-16',
              method: PaymentMethod.cash)),
          throwsA(isA<AppException>()));
      expect(
          () => repo.add(ExpenseInput(
              categoryId: c,
              amount: 10,
              spentAt: 'x',
              method: PaymentMethod.cash)),
          throwsA(isA<AppException>()));
    });

    test('مصروف اليوم يظهر في لوحة التحكم', () async {
      final repo = ExpenseRepository(appDb.db);
      final c = (await repo.categories()).first.id;
      await repo.add(ExpenseInput(
          categoryId: c,
          amount: 1234,
          spentAt: '2026-11-16',
          method: PaymentMethod.cash));
      final stats = await DashboardRepository(appDb.db, clock: () => now).load();
      expect(stats.expensesToday, 1234);
    });
  });

  group('الحضور', () {
    late AttendanceRepository att;
    late int enr;
    late int batchId;

    setUp(() async {
      att = AttendanceRepository(appDb.db, clock: () => now);
      enr = await seedEnrollment(appDb.db, originalFee: 1000);
      batchId = (await appDb.db.query('enrollments',
              where: 'id = ?', whereArgs: [enr]))
          .first['batch_id'] as int;
    });

    test('حفظ ثم تعديل مع تدقيق، ومنع التكرار', () async {
      await att.save(batchId, '2026-11-15',
          [AttendanceSaveItem(enr, AttendanceStatus.present)]);
      final n = await att.save(batchId, '2026-11-15',
          [AttendanceSaveItem(enr, AttendanceStatus.absent)]);
      expect(n, 1);
      final rows = await appDb.db.query('attendance');
      expect(rows.length, 1);
      expect(rows.first['status'], 'absent');
      final audits = await appDb.db.query('audit_logs',
          where: "entity = 'attendance' AND action = 'update'");
      expect(audits.length, 1);
    });

    test('رفض التاريخ المستقبلي', () {
      expect(
          () => att.save(batchId, '2026-11-20',
              [AttendanceSaveItem(enr, AttendanceStatus.present)]),
          throwsA(isA<AppException>()));
    });

    test('نسبة الحضور = (حاضر + متأخر) ÷ الكل', () async {
      for (final e in {
        '2026-11-10': AttendanceStatus.present,
        '2026-11-11': AttendanceStatus.late,
        '2026-11-12': AttendanceStatus.absent,
        '2026-11-13': AttendanceStatus.excused,
      }.entries) {
        await att.save(batchId, e.key, [AttendanceSaveItem(enr, e.value)]);
      }
      final stats = await att.report(batchId, '2026-11-01', '2026-11-30');
      expect(stats.single.total, 4);
      expect(stats.single.rate, 0.5);
    });
  });
}
