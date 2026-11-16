import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fees/core/database/app_database.dart';
import 'package:smart_fees/core/errors/app_exception.dart';
import 'package:smart_fees/features/fees/data/fee_plan_repository.dart';
import 'package:smart_fees/features/payments/data/payment_repository.dart';

import '../helpers/test_db.dart';

void main() {
  late AppDatabase appDb;
  late PaymentRepository payments;
  late FeePlanRepository plans;
  final fixedNow = DateTime(2026, 11, 16);

  setUp(() async {
    appDb = await openTestDb();
    payments = PaymentRepository(appDb.db, clock: () => fixedNow);
    plans = FeePlanRepository(appDb.db, clock: () => fixedNow);
  });

  tearDown(() async => appDb.close());

  Future<PaymentResult> pay(int enr, int amount,
          {String? receipt, Map<int, int>? manual, bool over = false}) =>
      payments.recordPayment(
        enrollmentId: enr,
        amount: amount,
        paidAt: '2026-11-16',
        method: PaymentMethod.cash,
        receiptNo: receipt,
        manualAllocations: manual,
        allowOverpayment: over,
      );

  Future<int> count(String table) async =>
      (await appDb.db.rawQuery('SELECT COUNT(*) c FROM $table')).first['c'] as int;

  test('الرسوم 50,000 والمدفوع 20,000 => المتبقي 30,000', () async {
    final enr = await seedEnrollment(appDb.db, originalFee: 50000);
    await pay(enr, 20000);
    final b = await payments.getBalance(enr);
    expect(b.paid, 20000);
    expect(b.remaining, 30000);
  });

  test('الرسوم 50,000 وخصم 5,000 ومدفوع 15,000 => المتبقي 30,000', () async {
    final enr =
        await seedEnrollment(appDb.db, originalFee: 50000, discount: 5000);
    await pay(enr, 15000);
    final b = await payments.getBalance(enr);
    expect(b.finalFee, 45000);
    expect(b.remaining, 30000);
  });

  test('خطة تقسيط 10,000 على قسطين', () async {
    final enr = await seedEnrollment(appDb.db, originalFee: 10000);
    await plans.createEqualPlan(
        enrollmentId: enr,
        count: 2,
        firstDue: DateTime(2026, 12, 1),
        intervalDays: 30);
    final rows = await appDb.db
        .query('installments', where: 'enrollment_id = ?', whereArgs: [enr], orderBy: 'seq');
    expect(rows.map((r) => r['amount']).toList(), [5000, 5000]);
  });

  test('دفع قسط جزئيًا', () async {
    final enr = await seedEnrollment(appDb.db, originalFee: 10000);
    await plans.createEqualPlan(
        enrollmentId: enr, count: 2, firstDue: DateTime(2026, 12, 1), intervalDays: 30);
    await pay(enr, 3000);
    final first = (await appDb.db.query('installments',
            where: 'enrollment_id = ? AND seq = 1', whereArgs: [enr]))
        .first;
    expect(first['paid_amount'], 3000);
    expect(first['status'], 'partial');
  });

  test('دفعة واحدة تغطي أكثر من قسط', () async {
    final enr = await seedEnrollment(appDb.db, originalFee: 10000);
    await plans.createEqualPlan(
        enrollmentId: enr, count: 2, firstDue: DateTime(2026, 12, 1), intervalDays: 30);
    final r = await pay(enr, 7500);
    expect(r.allocations.map((a) => a.amount).toList(), [5000, 2500]);
    final rows = await appDb.db
        .query('installments', where: 'enrollment_id = ?', whereArgs: [enr], orderBy: 'seq');
    expect(rows[0]['status'], 'paid');
    expect(rows[1]['paid_amount'], 2500);
  });

  test('عكس دفعة يعيد احتساب الرصيد دون حذف السجلات', () async {
    final enr = await seedEnrollment(appDb.db, originalFee: 10000);
    await plans.createEqualPlan(
        enrollmentId: enr, count: 2, firstDue: DateTime(2026, 12, 1), intervalDays: 30);
    final r = await pay(enr, 7500);
    await payments.reversePayment(paymentId: r.paymentId, reason: 'خطأ في الإدخال');

    expect((await payments.getBalance(enr)).remaining, 10000);
    final inst = await appDb.db.query('installments', where: 'enrollment_id = ?', whereArgs: [enr]);
    expect(inst.every((i) => i['paid_amount'] == 0), isTrue);
    final p = (await appDb.db.query('payments', where: 'id = ?', whereArgs: [r.paymentId])).first;
    expect(p['status'], 'reversed');
    expect(p['reversal_reason'], 'خطأ في الإدخال');
    final rc = (await appDb.db.query('receipts', where: 'payment_id = ?', whereArgs: [r.paymentId])).first;
    expect(rc['status'], 'cancelled');
    expect(await count('payments'), 1);
  });

  test('عكس دفعة يتطلب سببًا ولا يتكرر', () async {
    final enr = await seedEnrollment(appDb.db, originalFee: 1000);
    final r = await pay(enr, 500);
    expect(() => payments.reversePayment(paymentId: r.paymentId, reason: '  '),
        throwsA(isA<AppException>()));
    await payments.reversePayment(paymentId: r.paymentId, reason: 'سبب');
    expect(() => payments.reversePayment(paymentId: r.paymentId, reason: 'سبب'),
        throwsA(isA<AppException>()));
  });

  test('منع المبلغ السالب والصفر', () async {
    final enr = await seedEnrollment(appDb.db, originalFee: 1000);
    expect(() => pay(enr, -5), throwsA(isA<AppException>()));
    expect(() => pay(enr, 0), throwsA(isA<AppException>()));
    expect(await count('payments'), 0);
  });

  test('منع تخصيص أكبر من الدفعة مع تراجع كامل', () async {
    final enr = await seedEnrollment(appDb.db, originalFee: 10000);
    await plans.createEqualPlan(
        enrollmentId: enr, count: 2, firstDue: DateTime(2026, 12, 1), intervalDays: 30);
    final ids = (await appDb.db.query('installments',
            columns: ['id'], where: 'enrollment_id = ?', whereArgs: [enr], orderBy: 'seq'))
        .map((r) => r['id'] as int)
        .toList();
    await expectLater(
        pay(enr, 3000, manual: {ids[0]: 2000, ids[1]: 2000}),
        throwsA(isA<AppException>()));
    expect(await count('payments'), 0);
    expect(await count('payment_allocations'), 0);
    expect(await count('receipts'), 0);
  });

  test('منع تكرار رقم السند', () async {
    final enr = await seedEnrollment(appDb.db, originalFee: 10000);
    await pay(enr, 1000, receipt: 'R-X1');
    await expectLater(pay(enr, 1000, receipt: 'R-X1'), throwsA(isA<AppException>()));
    expect(await count('payments'), 1);
  });

  test('الأرقام التلقائية للسندات متسلسلة وفريدة', () async {
    final enr = await seedEnrollment(appDb.db, originalFee: 10000);
    final a = await pay(enr, 1000);
    final b = await pay(enr, 1000);
    expect(a.receiptNo, 'R-000001');
    expect(b.receiptNo, 'R-000002');
  });

  test('الدفع الزائد مرفوض إلا باعتماد صريح (رصيد دائن)', () async {
    final enr = await seedEnrollment(appDb.db, originalFee: 1000);
    await expectLater(pay(enr, 1500), throwsA(isA<AppException>()));
    final r = await pay(enr, 1500, over: true);
    expect(r.onAccountAmount, 1500);
    expect((await payments.getBalance(enr)).credit, 500);
  });

  test('لا يمكن حذف عملية مالية نهائيًا', () async {
    final enr = await seedEnrollment(appDb.db, originalFee: 1000);
    await pay(enr, 500);
    // التريغر يرفض الحذف برسالة عربية.
    await expectLater(appDb.db.delete('payments'), throwsA(anything));
    expect(await count('payments'), 1);
  });
}
