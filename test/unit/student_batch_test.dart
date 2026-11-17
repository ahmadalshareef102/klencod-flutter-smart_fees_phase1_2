import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fees/core/database/app_database.dart';
import 'package:smart_fees/core/errors/app_exception.dart';
import 'package:smart_fees/features/batches/data/batch_repository.dart';
import 'package:smart_fees/features/batches/domain/batch_type.dart';
import 'package:smart_fees/features/dashboard/data/dashboard_repository.dart';
import 'package:smart_fees/features/fees/data/fee_plan_repository.dart';
import 'package:smart_fees/features/installments/data/accrual_service.dart';
import 'package:smart_fees/features/payments/data/payment_repository.dart';
import 'package:smart_fees/features/students/data/student_repository.dart';

import '../helpers/test_db.dart';

void main() {
  late AppDatabase appDb;
  late BatchRepository batches;
  late StudentRepository students;
  late PaymentRepository payments;
  var now = DateTime(2026, 11, 16);

  setUp(() async {
    now = DateTime(2026, 11, 16);
    appDb = await openTestDb();
    batches = BatchRepository(appDb.db);
    payments = PaymentRepository(appDb.db, clock: () => now);
    students = StudentRepository(
      appDb.db,
      FeePlanRepository(appDb.db, clock: () => now),
      payments,
      clock: () => now,
    );
  });

  tearDown(() async => appDb.close());

  Future<int> mkBatch(BatchType type,
          {int fee = 10000, String? end, int count = 1, String name = 'ب'}) =>
      batches.create(BatchInput(
        name: name,
        type: type,
        fee: fee,
        startDate: '2026-11-01',
        endDate: end,
        installmentsCount: count,
      ));

  StudentInput st(String name, {String? no}) => StudentInput(
      fullName: name, studentNo: no, registeredAt: '2026-11-16');

  Future<List<Map<String, Object?>>> installmentsOf(int enrollmentId) =>
      appDb.db.query('installments',
          where: 'enrollment_id = ?', whereArgs: [enrollmentId], orderBy: 'seq');

  group('الدفعات', () {
    test('إنشاء دفعة وقراءتها مع عدد الطلاب', () async {
      final b = await mkBatch(BatchType.custom);
      final list = await batches.list();
      expect(list.single.id, b);
      expect(list.single.studentCount, 0);
    });

    test('يرفض اسمًا فارغًا ومبلغًا صفرًا واسمًا مكررًا', () async {
      await mkBatch(BatchType.custom, name: 'مكرر');
      expect(() => mkBatch(BatchType.custom, name: 'مكرر'),
          throwsA(isA<AppException>()));
      expect(() => mkBatch(BatchType.custom, name: ' '),
          throwsA(isA<AppException>()));
      expect(() => mkBatch(BatchType.custom, fee: 0, name: 'ج'),
          throwsA(isA<AppException>()));
    });

    test('نوع إجمالي الشهري يتطلب تاريخ انتهاء', () async {
      expect(() => mkBatch(BatchType.monthlyTotal),
          throwsA(isA<AppException>()));
    });
  });

  group('الطلاب والتسجيل', () {
    test('إضافة طالب بلا دفعة، ورقم القيد يُولَّد', () async {
      final a = await students.createStudent(st('أحمد'));
      final b = await students.createStudent(st('علي'));
      final list = await students.list();
      expect(list.length, 2);
      expect(list.map((s) => s.studentNo).toSet().length, 2);
      expect(a != b, isTrue);
    });

    test('رقم القيد المكرر مرفوض ولا يُحفظ شيء', () async {
      await students.createStudent(st('أ', no: '100'));
      await expectLater(students.createStudent(st('ب', no: '100')),
          throwsA(isA<AppException>()));
      expect((await students.list()).length, 1);
    });

    test('بحث بالاسم والرقم والهاتف', () async {
      await students.createStudent(const StudentInput(
          fullName: 'أحمد سمر', phone: '777111', registeredAt: '2026-11-16'));
      await students.createStudent(st('خالد', no: '55'));
      expect((await students.list(query: 'سمر')).length, 1);
      expect((await students.list(query: '777')).length, 1);
      expect((await students.list(query: '55')).length, 1);
      expect((await students.list(query: 'لا يوجد')).length, 0);
    });

    test('تعديل الطالب لا يمس تسجيلاته', () async {
      final b = await mkBatch(BatchType.custom);
      final id = await students.createStudent(st('قديم'),
          enroll: EnrollInput(batchId: b, fee: 5000));
      await students.updateStudent(id, st('جديد'));
      final d = (await students.detail(id))!;
      expect(d.student['full_name'], 'جديد');
      expect(d.enrollments.single.finalFee, 5000);
    });

    test('الأرشفة تُخفي الطالب وتُبقي سجله المالي، والاستعادة تعيده', () async {
      final b = await mkBatch(BatchType.custom);
      final id = await students.createStudent(st('م'),
          enroll: EnrollInput(batchId: b, fee: 5000, paidNow: 2000));
      await students.archive(id);
      expect(await students.list(), isEmpty);
      expect((await students.list(archived: true)).length, 1);
      expect((await students.detail(id))!.totalPaid, 2000);
      await students.restore(id);
      expect((await students.list()).length, 1);
    });

    test('تسجيل مع خصم ودفعة أولى: الرصيد صحيح', () async {
      final b = await mkBatch(BatchType.custom, fee: 50000);
      final id = await students.createStudent(st('ط'),
          enroll: EnrollInput(
              batchId: b, fee: 50000, discount: 5000, paidNow: 15000));
      final d = (await students.detail(id))!;
      expect(d.totalFees, 45000);
      expect(d.totalPaid, 15000);
      expect(d.remaining, 30000);
    });

    test('فشل الدفعة الأولى يتراجع عن الطالب والتسجيل كاملين', () async {
      final b = await mkBatch(BatchType.custom, fee: 1000);
      await expectLater(
        students.createStudent(st('ط'),
            enroll: EnrollInput(batchId: b, fee: 1000, paidNow: 5000)),
        throwsA(isA<AppException>()),
      );
      expect(await students.list(), isEmpty);
      expect((await appDb.db.query('enrollments')), isEmpty);
      expect((await appDb.db.query('fee_plans')), isEmpty);
    });

    test('لا تسجيل مكرر في نفس الدفعة، ولا خصم يساوي الرسوم', () async {
      final b = await mkBatch(BatchType.custom, fee: 1000);
      final id = await students.createStudent(st('ط'),
          enroll: EnrollInput(batchId: b, fee: 1000));
      await expectLater(students.addEnrollment(id, EnrollInput(batchId: b, fee: 1000)),
          throwsA(isA<AppException>()));
      final id2 = await students.createStudent(st('ي'));
      await expectLater(
          students.addEnrollment(id2, EnrollInput(batchId: b, fee: 1000, discount: 1000)),
          throwsA(isA<AppException>()));
    });

    test('طالب في أكثر من دفعة', () async {
      final b1 = await mkBatch(BatchType.custom, name: 'د1');
      final b2 = await mkBatch(BatchType.custom, name: 'د2');
      final id = await students.createStudent(st('ط'),
          enroll: EnrollInput(batchId: b1, fee: 1000));
      await students.addEnrollment(id, EnrollInput(batchId: b2, fee: 2000));
      final d = (await students.detail(id))!;
      expect(d.enrollments.length, 2);
      expect(d.totalFees, 3000);
    });
  });

  group('خطط الأقساط بحسب النوع', () {
    test('أقساط: 10,000 على 3 والمجموع مطابق', () async {
      final b = await mkBatch(BatchType.installments, count: 3);
      final id = await students.createStudent(st('ط'),
          enroll: EnrollInput(batchId: b, fee: 10000));
      final e = (await students.detail(id))!.enrollments.single;
      expect(e.installments.map((i) => i.amount).toList(), [3334, 3333, 3333]);
      expect(e.installments.fold<int>(0, (s, i) => s + i.amount), 10000);
    });

    test('إجمالي شهري: يُقسَّم على أشهر الدفعة', () async {
      final b = await mkBatch(BatchType.monthlyTotal,
          fee: 9000, end: '2027-01-31'); // نحو 3 أشهر
      final id = await students.createStudent(st('ط'),
          enroll: EnrollInput(batchId: b, fee: 9000));
      final e = (await students.detail(id))!.enrollments.single;
      expect(e.installments.length, greaterThan(1));
      expect(e.installments.fold<int>(0, (s, i) => s + i.amount), 9000);
    });

    test('مخصص: قسط واحد', () async {
      final b = await mkBatch(BatchType.custom);
      final id = await students.createStudent(st('ط'),
          enroll: EnrollInput(batchId: b, fee: 7000));
      expect((await students.detail(id))!.enrollments.single.installments.length, 1);
    });

    test('الخصم لا يُطبَّق على الرسوم المتكررة', () async {
      final b = await mkBatch(BatchType.monthlyRecurring, fee: 5000);
      final id = await students.createStudent(st('ط'),
          enroll: EnrollInput(batchId: b, fee: 5000, discount: 1000));
      expect((await students.detail(id))!.totalFees, 5000);
    });
  });

  group('الرسوم الشهرية المتكررة', () {
    test('شهر واحد عند التسجيل، ثم شهر جديد عند حلول موعده فيزيد الإجمالي', () async {
      final b = await mkBatch(BatchType.monthlyRecurring, fee: 5000);
      final id = await students.createStudent(st('ط'),
          enroll: EnrollInput(batchId: b, fee: 5000, paidNow: 5000));
      final accrual = AccrualService(appDb.db, clock: () => now);

      expect(await accrual.run(), 0); // نفس اليوم: لا جديد
      expect((await students.detail(id))!.totalFees, 5000);

      now = DateTime(2026, 12, 16); // بعد شهر بالضبط
      expect(await accrual.run(), 1);
      expect(await accrual.run(), 0); // لا تكرار
      var d = (await students.detail(id))!;
      expect(d.totalFees, 10000);
      expect(d.remaining, 5000);
      expect(d.enrollments.single.installments.length, 2);

      now = DateTime(2027, 2, 20); // شهران إضافيان
      expect(await accrual.run(), 2);
      d = (await students.detail(id))!;
      expect(d.totalFees, 20000);
      // قسط ديسمبر وما بعده غير مسدد ومتأخر.
      final inst = d.enrollments.single.installments;
      expect(inst.first.status, 'paid');
      expect(inst.skip(1).every((i) => i.status == 'late'), isTrue);
    });

    test('الربع السنوي يضيف كل 3 أشهر', () async {
      final b = await mkBatch(BatchType.quarterly, fee: 30000);
      final id = await students.createStudent(st('ط'),
          enroll: EnrollInput(batchId: b, fee: 30000));
      final accrual = AccrualService(appDb.db, clock: () => now);
      now = DateTime(2027, 2, 15); // أقل من 3 أشهر
      expect(await accrual.run(), 0);
      now = DateTime(2027, 2, 16);
      expect(await accrual.run(), 1);
      expect((await students.detail(id))!.totalFees, 60000);
    });

    test('لا تُحتسب فترات بعد تاريخ نهاية الدفعة أو مع إغلاقها', () async {
      final b = await mkBatch(BatchType.monthlyRecurring,
          fee: 1000, end: '2026-12-31', name: 'محدودة');
      final id = await students.createStudent(st('ط'),
          enroll: EnrollInput(batchId: b, fee: 1000));
      final accrual = AccrualService(appDb.db, clock: () => now);
      now = DateTime(2027, 6, 1);
      await accrual.run();
      // 16 نوفمبر و16 ديسمبر فقط (قبل 31 ديسمبر).
      expect((await students.detail(id))!.totalFees, 2000);

      final b2 = await mkBatch(BatchType.monthlyRecurring, fee: 1000, name: 'تُغلق');
      final id2 = await students.createStudent(st('ي'),
          enroll: EnrollInput(batchId: b2, fee: 1000));
      await batches.setStatus(b2, 'closed');
      now = DateTime(2028, 1, 1);
      await accrual.run();
      expect((await students.detail(id2))!.totalFees, 1000);
    });

    test('الدفع بعد التراكم يُخصَّص للأقدم أولًا', () async {
      final b = await mkBatch(BatchType.monthlyRecurring, fee: 5000);
      final id = await students.createStudent(st('ط'),
          enroll: EnrollInput(batchId: b, fee: 5000));
      now = DateTime(2027, 1, 16); // 3 أقساط
      await AccrualService(appDb.db, clock: () => now).run();
      final enrId = (await students.detail(id))!.enrollments.single.id;
      await payments.recordPayment(
          enrollmentId: enrId,
          amount: 7500,
          paidAt: '2027-01-16',
          method: PaymentMethod.cash);
      final inst = (await installmentsOf(enrId));
      expect(inst.map((i) => i['paid_amount']).toList(), [5000, 2500, 0]);
    });
  });

  group('لوحة القيادة', () {
    test('الأرقام تطابق قاعدة البيانات', () async {
      final b = await mkBatch(BatchType.installments, fee: 10000, count: 2);
      await students.createStudent(st('أ'),
          enroll: EnrollInput(batchId: b, fee: 10000, paidNow: 4000));
      await students.createStudent(st('ب'),
          enroll: EnrollInput(batchId: b, fee: 10000));
      await students.createStudent(st('ج')); // بلا دفعة

      final s = await DashboardRepository(appDb.db, clock: () => now).load();
      expect(s.batches, 1);
      expect(s.students, 3);
      expect(s.recentStudents, 3);
      expect(s.totalFees, 20000);
      expect(s.collected, 4000);
      expect(s.remaining, 16000);
      expect(s.collectedToday, 4000);
      expect(s.lateStudents, 0);
      expect(s.collectedRatio, closeTo(0.2, 1e-9));

      // بعد تجاوز موعد القسط الأول يصبح الطالبان متأخرين.
      now = DateTime(2026, 11, 20);
      await AccrualService(appDb.db, clock: () => now).run();
      final late = await DashboardRepository(appDb.db, clock: () => now).load();
      expect(late.lateStudents, 2);
    });

    test('عكس دفعة يُحدّث المحصَّل', () async {
      final b = await mkBatch(BatchType.custom, fee: 5000);
      final id = await students.createStudent(st('أ'),
          enroll: EnrollInput(batchId: b, fee: 5000, paidNow: 5000));
      final pid = (await students.detail(id))!.payments.single.id;
      await payments.reversePayment(paymentId: pid, reason: 'خطأ');
      final s = await DashboardRepository(appDb.db, clock: () => now).load();
      expect(s.collected, 0);
      expect(s.remaining, 5000);
    });
  });
}
