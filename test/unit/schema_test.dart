import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fees/core/database/app_database.dart';

import '../helpers/test_db.dart';

void main() {
  late AppDatabase appDb;

  setUp(() async => appDb = await openTestDb());
  tearDown(() async => appDb.close());

  test('المفاتيح الأجنبية مفعّلة', () async {
    final r = await appDb.db.rawQuery('PRAGMA foreign_keys');
    expect(r.first.values.first, 1);
  });

  test('تسجيل لطالب غير موجود يفشل', () async {
    final course = await appDb.db.insert('courses', {'name': 'د', 'default_fee': 0});
    await expectLater(
      appDb.db.insert('enrollments', {
        'student_id': 9999,
        'course_id': course,
        'original_fee': 100,
        'final_fee': 100,
      }),
      throwsA(anything),
    );
  });

  test('قيد CHECK: الرسوم النهائية يجب أن تطابق المعادلة', () async {
    await seedEnrollment(appDb.db, originalFee: 1000); // أرقام صحيحة تنجح
    final institute = await appDb.db.insert('institutes', {'name': 'م'});
    final s = await appDb.db.insert('students',
        {'institute_id': institute, 'student_no': 'Z1', 'full_name': 'ط'});
    final c = await appDb.db.insert('courses', {'name': 'د'});
    await expectLater(
      appDb.db.insert('enrollments', {
        'student_id': s,
        'course_id': c,
        'original_fee': 1000,
        'discount': 100,
        'final_fee': 1000, // خطأ: يجب 900
      }),
      throwsA(anything),
    );
  });

  test('أرشفة طالب (حذف ناعم) لا تفقد تسجيلاته أو سجله المالي', () async {
    final enr = await seedEnrollment(appDb.db, originalFee: 1000);
    final studentId = (await appDb.db.query('enrollments',
            columns: ['student_id'], where: 'id = ?', whereArgs: [enr]))
        .first['student_id'] as int;
    await appDb.db.update(
        'students', {'deleted_at': DateTime.now().toUtc().toIso8601String()},
        where: 'id = ?', whereArgs: [studentId]);
    expect(
        (await appDb.db.query('enrollments', where: 'id = ?', whereArgs: [enr])).length, 1);
    // الحذف النهائي لطالب له تسجيلات ممنوع بالمفتاح الأجنبي.
    await expectLater(
        appDb.db.delete('students', where: 'id = ?', whereArgs: [studentId]),
        throwsA(anything));
  });

  test('إيقاف دورة لا يحذف سجلاتها', () async {
    final enr = await seedEnrollment(appDb.db, originalFee: 1000);
    final courseId = (await appDb.db.query('enrollments',
            columns: ['course_id'], where: 'id = ?', whereArgs: [enr]))
        .first['course_id'] as int;
    await appDb.db.update('courses', {'status': 'suspended'},
        where: 'id = ?', whereArgs: [courseId]);
    expect(
        (await appDb.db.query('enrollments', where: 'id = ?', whereArgs: [enr])).length, 1);
  });

  test('منع تكرار الحضور لنفس التسجيل والتاريخ والجلسة', () async {
    final enr = await seedEnrollment(appDb.db, originalFee: 1000);
    final batchId = (await appDb.db.query('enrollments',
            columns: ['batch_id'], where: 'id = ?', whereArgs: [enr]))
        .first['batch_id'] as int;
    final row = {
      'enrollment_id': enr,
      'batch_id': batchId,
      'date': '2026-11-16',
      'status': 'present',
    };
    await appDb.db.insert('attendance', row);
    await expectLater(appDb.db.insert('attendance', row), throwsA(anything));
  });

  test('سجل التدقيق غير قابل للتعديل أو الحذف', () async {
    final id = await appDb.db.insert(
        'audit_logs', {'entity': 'x', 'action': 'a'});
    await expectLater(
        appDb.db.update('audit_logs', {'action': 'b'}, where: 'id = ?', whereArgs: [id]),
        throwsA(anything));
    await expectLater(
        appDb.db.delete('audit_logs', where: 'id = ?', whereArgs: [id]),
        throwsA(anything));
  });

  test('التصنيفات الافتراضية للمصروفات موجودة', () async {
    final r = await appDb.db.rawQuery('SELECT COUNT(*) c FROM expense_categories');
    expect(r.first['c'], 7);
  });
}
