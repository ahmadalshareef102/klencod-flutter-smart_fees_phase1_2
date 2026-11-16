import 'package:smart_fees/core/database/app_database.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// قاعدة بيانات في الذاكرة للاختبارات فقط (بيانات الاختبار لا تدخل التطبيق).
Future<AppDatabase> openTestDb() async {
  sqfliteFfiInit();
  return AppDatabase.openWith(databaseFactoryFfi, inMemoryDatabasePath);
}

int _seq = 0;

/// ينشئ معهدًا وطالبًا ودورة ودفعة وتسجيلًا، ويعيد معرّف التسجيل.
Future<int> seedEnrollment(
  Database db, {
  required int originalFee,
  int discount = 0,
  int extra = 0,
}) async {
  _seq++;
  final institute = await db.insert('institutes', {'name': 'معهد اختبار'});
  final student = await db.insert('students', {
    'institute_id': institute,
    'student_no': 'S-$_seq',
    'full_name': 'طالب اختبار $_seq',
  });
  final course = await db.insert('courses', {
    'institute_id': institute,
    'name': 'دورة اختبار $_seq',
    'default_fee': originalFee,
  });
  final batch = await db.insert('batches', {
    'course_id': course,
    'name': 'الدفعة الأولى',
  });
  return db.insert('enrollments', {
    'student_id': student,
    'course_id': course,
    'batch_id': batch,
    'enrolled_at': '2026-11-01',
    'original_fee': originalFee,
    'discount': discount,
    'extra_fee': extra,
    'final_fee': originalFee - discount + extra,
  });
}
