import 'package:sqflite/sqflite.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/helpers/date_range.dart';
import '../../../core/helpers/dates.dart';
import '../../../core/helpers/money.dart';
import '../../attendance/data/attendance_repository.dart';
import '../domain/report_data.dart';

/// بناء كل التقارير من قاعدة البيانات. الأرقام هنا هي نفسها في الشاشات.
class ReportRepository {
  ReportRepository(this._db, this._attendance, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Database _db;
  final AttendanceRepository _attendance;
  final DateTime Function() _clock;

  String get _today => Dates.iso(_clock());

  static String methodLabel(String c) => switch (c) {
        'cash' => 'نقدًا',
        'transfer' => 'تحويل',
        _ => 'أخرى',
      };

  static String studentStatusLabel(String c) => switch (c) {
        'active' => 'نشط',
        'suspended' => 'متوقف',
        'graduated' => 'متخرج',
        'withdrawn' => 'منسحب',
        _ => c,
      };

  static List<MapEntry<String, String>> _sum(Map<String, Object> m) => [
        for (final e in m.entries)
          MapEntry(e.key, e.value is int ? Money.format(e.value as int) : '${e.value}'),
      ];

  // ------------------------------------------------------------- التحصيل

  /// تقرير التحصيل لفترة (اليومي = فترة يوم واحد).
  Future<ReportData> collections(DateRange r, {String? title}) async {
    final rows = await _db.rawQuery('''
      SELECT p.paid_at, p.receipt_no, s.full_name, COALESCE(b.name, '—') AS bname,
             p.method, p.amount
      FROM payments p
      JOIN enrollments e ON e.id = p.enrollment_id
      JOIN students s ON s.id = e.student_id
      LEFT JOIN batches b ON b.id = e.batch_id
      WHERE p.status = 'active' AND p.paid_at BETWEEN ? AND ?
      ORDER BY p.paid_at, p.id''', [r.from, r.to]);
    var total = 0;
    final out = <List<Object>>[];
    for (final x in rows) {
      final a = x['amount'] as int;
      total += a;
      out.add([
        x['paid_at'] as String,
        x['receipt_no'] as String,
        x['full_name'] as String,
        x['bname'] as String,
        methodLabel(x['method'] as String),
        a,
      ]);
    }
    return ReportData(
      title: title ?? 'تقرير التحصيل',
      subtitle: r.label,
      columns: const ['التاريخ', 'رقم السند', 'الطالب', 'الدفعة', 'الطريقة', 'المبلغ (ر.ي)'],
      rows: out,
      summary: _sum({'عدد السندات': out.length, 'إجمالي التحصيل': total}),
    );
  }

  Future<ReportData> collectionsByBatch(DateRange r) async {
    final rows = await _db.rawQuery('''
      SELECT COALESCE(b.name, 'بدون دفعة') AS n, COUNT(*) AS c, SUM(p.amount) AS t
      FROM payments p
      JOIN enrollments e ON e.id = p.enrollment_id
      LEFT JOIN batches b ON b.id = e.batch_id
      WHERE p.status = 'active' AND p.paid_at BETWEEN ? AND ?
      GROUP BY e.batch_id ORDER BY t DESC''', [r.from, r.to]);
    var total = 0;
    final out = <List<Object>>[];
    for (final x in rows) {
      final t = (x['t'] as num).toInt();
      total += t;
      out.add([x['n'] as String, (x['c'] as num).toInt(), t]);
    }
    return ReportData(
      title: 'التحصيل حسب الدفعة',
      subtitle: r.label,
      columns: const ['الدفعة', 'عدد السندات', 'المبلغ (ر.ي)'],
      rows: out,
      summary: _sum({'الإجمالي': total}),
    );
  }

  // ----------------------------------------------- أرصدة الطلاب والمتأخرات

  Future<List<Map<String, Object?>>> _balances({int? batchId}) {
    return _db.rawQuery('''
      SELECT s.full_name, s.student_no, COALESCE(b.name, '—') AS bname,
             e.final_fee AS fee, e.discount AS discount, e.original_fee AS orig,
        (SELECT COALESCE(SUM(p.amount), 0) FROM payments p
          WHERE p.enrollment_id = e.id AND p.status = 'active') AS paid
      FROM enrollments e
      JOIN students s ON s.id = e.student_id
      LEFT JOIN batches b ON b.id = e.batch_id
      WHERE e.status = 'active' AND s.deleted_at IS NULL
        ${batchId == null ? '' : 'AND e.batch_id = ?'}
      ORDER BY s.full_name COLLATE NOCASE''', batchId == null ? [] : [batchId]);
  }

  Future<ReportData> unpaidStudents() async {
    final rows = (await _balances())
        .where((r) => (r['fee'] as int) > 0 && (r['paid'] as num) == 0)
        .toList();
    var total = 0;
    final out = <List<Object>>[];
    for (final r in rows) {
      final fee = r['fee'] as int;
      total += fee;
      out.add([r['full_name'] as String, r['student_no'] as String, r['bname'] as String, fee]);
    }
    return ReportData(
      title: 'الطلاب غير الدافعين',
      subtitle: 'حتى $_today',
      columns: const ['الطالب', 'رقم القيد', 'الدفعة', 'الرسوم (ر.ي)'],
      rows: out,
      summary: _sum({'عدد الطلاب': out.length, 'إجمالي المستحق': total}),
    );
  }

  Future<ReportData> partialStudents() async {
    final rows = (await _balances()).where((r) {
      final paid = (r['paid'] as num).toInt();
      return paid > 0 && paid < (r['fee'] as int);
    });
    var rem = 0;
    final out = <List<Object>>[];
    for (final r in rows) {
      final fee = r['fee'] as int;
      final paid = (r['paid'] as num).toInt();
      rem += fee - paid;
      out.add([
        r['full_name'] as String,
        r['bname'] as String,
        fee,
        paid,
        fee - paid,
      ]);
    }
    return ReportData(
      title: 'الطلاب ذوو الدفع الجزئي',
      subtitle: 'حتى $_today',
      columns: const ['الطالب', 'الدفعة', 'الرسوم', 'المدفوع', 'المتبقي'],
      rows: out,
      summary: _sum({'عدد الطلاب': out.length, 'إجمالي المتبقي': rem}),
    );
  }

  Future<ReportData> lateInstallments() async {
    final rows = await _db.rawQuery('''
      SELECT s.full_name, s.student_no, COALESCE(b.name, '—') AS bname, i.seq,
             i.due_date, (i.amount - i.paid_amount) AS rem,
             CAST(julianday(?) - julianday(i.due_date) AS INTEGER) AS days
      FROM installments i
      JOIN enrollments e ON e.id = i.enrollment_id
      JOIN students s ON s.id = e.student_id
      LEFT JOIN batches b ON b.id = e.batch_id
      WHERE e.status = 'active' AND s.deleted_at IS NULL
        AND i.paid_amount < i.amount AND i.due_date < ?
      ORDER BY i.due_date, s.full_name COLLATE NOCASE''', [_today, _today]);
    var total = 0;
    final students = <String>{};
    final out = <List<Object>>[];
    for (final x in rows) {
      final rem = x['rem'] as int;
      total += rem;
      students.add(x['student_no'] as String);
      out.add([
        x['full_name'] as String,
        x['bname'] as String,
        x['seq'] as int,
        x['due_date'] as String,
        (x['days'] as num).toInt(),
        rem,
      ]);
    }
    return ReportData(
      title: 'تقرير المتأخرات',
      subtitle: 'حتى $_today',
      columns: const ['الطالب', 'الدفعة', 'القسط', 'تاريخ الاستحقاق', 'أيام التأخر', 'المتبقي (ر.ي)'],
      rows: out,
      summary: _sum({
        'عدد الطلاب المتأخرين': students.length,
        'عدد الأقساط المتأخرة': out.length,
        'إجمالي المتأخرات': total,
      }),
    );
  }

  /// أقساط مستحقة اليوم أو خلال [days] يومًا القادمة.
  Future<ReportData> dueInstallments({int days = 30}) async {
    final until = Dates.iso(_clock().add(Duration(days: days)));
    final rows = await _db.rawQuery('''
      SELECT s.full_name, COALESCE(b.name, '—') AS bname, i.seq, i.due_date,
             (i.amount - i.paid_amount) AS rem
      FROM installments i
      JOIN enrollments e ON e.id = i.enrollment_id
      JOIN students s ON s.id = e.student_id
      LEFT JOIN batches b ON b.id = e.batch_id
      WHERE e.status = 'active' AND s.deleted_at IS NULL
        AND i.paid_amount < i.amount AND i.due_date BETWEEN ? AND ?
      ORDER BY i.due_date, s.full_name COLLATE NOCASE''', [_today, until]);
    var total = 0;
    final out = <List<Object>>[];
    for (final x in rows) {
      final rem = x['rem'] as int;
      total += rem;
      out.add([
        x['full_name'] as String,
        x['bname'] as String,
        x['seq'] as int,
        x['due_date'] as String,
        rem,
      ]);
    }
    return ReportData(
      title: 'الأقساط المستحقة',
      subtitle: 'من $_today إلى $until',
      columns: const ['الطالب', 'الدفعة', 'القسط', 'تاريخ الاستحقاق', 'المتبقي (ر.ي)'],
      rows: out,
      summary: _sum({'عدد الأقساط': out.length, 'الإجمالي': total}),
    );
  }

  Future<ReportData> discounts() async {
    final rows = (await _balances()).where((r) => (r['discount'] as int) > 0);
    var total = 0;
    final out = <List<Object>>[];
    for (final r in rows) {
      final d = r['discount'] as int;
      total += d;
      out.add([r['full_name'] as String, r['bname'] as String, r['orig'] as int, d, r['fee'] as int]);
    }
    return ReportData(
      title: 'تقرير الخصومات',
      columns: const ['الطالب', 'الدفعة', 'الرسوم الأصلية', 'الخصم', 'الرسوم النهائية'],
      rows: out,
      summary: _sum({'عدد الخصومات': out.length, 'إجمالي الخصومات': total}),
    );
  }

  // --------------------------------------------------- المصروفات والتدفق

  Future<int> _collected(DateRange r) async {
    final x = await _db.rawQuery(
        "SELECT COALESCE(SUM(amount), 0) AS s FROM payments "
        "WHERE status = 'active' AND paid_at BETWEEN ? AND ?",
        [r.from, r.to]);
    return (x.first['s'] as num).toInt();
  }

  Future<int> _spent(DateRange r) async {
    final x = await _db.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) AS s FROM expenses '
        'WHERE deleted_at IS NULL AND spent_at BETWEEN ? AND ?',
        [r.from, r.to]);
    return (x.first['s'] as num).toInt();
  }

  Future<ReportData> expenses(DateRange r) async {
    final rows = await _db.rawQuery('''
      SELECT x.spent_at, c.name AS cat, x.description, x.method, x.amount
      FROM expenses x JOIN expense_categories c ON c.id = x.category_id
      WHERE x.deleted_at IS NULL AND x.spent_at BETWEEN ? AND ?
      ORDER BY x.spent_at, x.id''', [r.from, r.to]);
    var total = 0;
    final byCat = <String, int>{};
    final out = <List<Object>>[];
    for (final x in rows) {
      final a = x['amount'] as int;
      total += a;
      byCat[x['cat'] as String] = (byCat[x['cat'] as String] ?? 0) + a;
      out.add([
        x['spent_at'] as String,
        x['cat'] as String,
        (x['description'] as String?) ?? '',
        methodLabel(x['method'] as String),
        a,
      ]);
    }
    return ReportData(
      title: 'تقرير المصروفات',
      subtitle: r.label,
      columns: const ['التاريخ', 'النوع', 'الوصف', 'الطريقة', 'المبلغ (ر.ي)'],
      rows: out,
      summary: [
        for (final e in byCat.entries) MapEntry(e.key, Money.format(e.value)),
        MapEntry('إجمالي المصروفات', Money.format(total)),
      ],
    );
  }

  /// صافي التدفق = التحصيلات الفعلية − المصروفات. إجمالي الرسوم المستحقة
  /// يُعرض مستقلًا ولا يدخل في الصافي.
  Future<ReportData> netCashFlow(DateRange r) async {
    final collected = await _collected(r);
    final spent = await _spent(r);
    final fees = await _db.rawQuery('''
      SELECT COALESCE(SUM(e.final_fee), 0) AS s FROM enrollments e
      JOIN students s ON s.id = e.student_id
      WHERE s.deleted_at IS NULL AND e.status != 'cancelled' ''');
    final due = (fees.first['s'] as num).toInt();
    return ReportData(
      title: 'صافي التدفق المالي',
      subtitle: r.label,
      columns: const ['البند', 'المبلغ (ر.ي)'],
      rows: [
        ['التحصيلات الفعلية', collected],
        ['المصروفات المسجلة', spent],
        ['صافي التدفق النقدي', collected - spent],
      ],
      summary: _sum({'إجمالي الرسوم المستحقة (مستقل عن التدفق)': due}),
    );
  }

  // ------------------------------------------------------------- الكشوف

  Future<ReportData> studentStatement(int studentId) async {
    final st = await _db.query('students',
        where: 'id = ?', whereArgs: [studentId], limit: 1);
    if (st.isEmpty) throw const AppException('الطالب غير موجود');

    final inst = await _db.rawQuery('''
      SELECT i.due_date AS d, i.seq, i.amount, COALESCE(b.name, '—') AS bname
      FROM installments i JOIN enrollments e ON e.id = i.enrollment_id
      LEFT JOIN batches b ON b.id = e.batch_id
      WHERE e.student_id = ? AND e.status != 'cancelled' ''', [studentId]);
    final pays = await _db.rawQuery('''
      SELECT p.paid_at AS d, p.receipt_no, p.amount, COALESCE(b.name, '—') AS bname
      FROM payments p JOIN enrollments e ON e.id = p.enrollment_id
      LEFT JOIN batches b ON b.id = e.batch_id
      WHERE e.student_id = ? AND p.status = 'active' ''', [studentId]);

    // أحداث: (تاريخ، ترتيب، بيان، مدين، دائن). الاستحقاق يسبق الدفع في اليوم نفسه.
    final ev = <(String, int, String, int, int)>[
      for (final i in inst)
        (i['d'] as String, 0, 'قسط ${i['seq']} - ${i['bname']}', i['amount'] as int, 0),
      for (final p in pays)
        (p['d'] as String, 1, 'سند ${p['receipt_no']} - ${p['bname']}', 0, p['amount'] as int),
    ]..sort((a, b) {
        final c = a.$1.compareTo(b.$1);
        return c != 0 ? c : a.$2.compareTo(b.$2);
      });

    var debit = 0, credit = 0;
    final out = <List<Object>>[];
    for (final e in ev) {
      debit += e.$4;
      credit += e.$5;
      out.add([e.$1, e.$3, e.$4, e.$5, debit - credit]);
    }
    return ReportData(
      title: 'كشف حساب الطالب: ${st.first['full_name']}',
      subtitle: 'رقم القيد ${st.first['student_no']} • حتى $_today',
      columns: const ['التاريخ', 'البيان', 'مدين (رسوم)', 'دائن (مدفوع)', 'الرصيد'],
      rows: out,
      summary: _sum({
        'إجمالي الرسوم': debit,
        'إجمالي المدفوع': credit,
        'المتبقي': debit - credit,
      }),
    );
  }

  Future<ReportData> batchStatement(int batchId) async {
    final b = await _db.query('batches',
        where: 'id = ?', whereArgs: [batchId], limit: 1);
    if (b.isEmpty) throw const AppException('الدفعة غير موجودة');
    var fees = 0, paid = 0;
    final out = <List<Object>>[];
    for (final r in await _balances(batchId: batchId)) {
      final f = r['fee'] as int;
      final p = (r['paid'] as num).toInt();
      fees += f;
      paid += p;
      out.add([r['full_name'] as String, r['student_no'] as String, f, p, f - p]);
    }
    return ReportData(
      title: 'كشف حساب الدفعة: ${b.first['name']}',
      subtitle: 'حتى $_today',
      columns: const ['الطالب', 'رقم القيد', 'الرسوم', 'المدفوع', 'المتبقي'],
      rows: out,
      summary: _sum({
        'عدد الطلاب': out.length,
        'إجمالي الرسوم': fees,
        'إجمالي المدفوع': paid,
        'إجمالي المتبقي': fees - paid,
      }),
    );
  }

  Future<ReportData> instituteStatement() async {
    final rows = await _db.rawQuery('''
      SELECT COALESCE(b.name, 'بدون دفعة') AS n,
             COUNT(DISTINCT e.student_id) AS sc,
             SUM(e.final_fee) AS fees,
        (SELECT COALESCE(SUM(p.amount), 0) FROM payments p
           JOIN enrollments e2 ON e2.id = p.enrollment_id
           JOIN students s2 ON s2.id = e2.student_id
          WHERE e2.batch_id IS e.batch_id AND p.status = 'active'
            AND s2.deleted_at IS NULL) AS paid
      FROM enrollments e
      JOIN students s ON s.id = e.student_id
      LEFT JOIN batches b ON b.id = e.batch_id
      WHERE e.status != 'cancelled' AND s.deleted_at IS NULL
      GROUP BY e.batch_id ORDER BY n''');
    var fees = 0, paid = 0;
    final out = <List<Object>>[];
    for (final x in rows) {
      final f = (x['fees'] as num).toInt();
      final p = (x['paid'] as num).toInt();
      fees += f;
      paid += p;
      out.add([x['n'] as String, (x['sc'] as num).toInt(), f, p, f - p]);
    }
    return ReportData(
      title: 'كشف الحساب العام للمعهد',
      subtitle: 'حتى $_today',
      columns: const ['الدفعة', 'الطلاب', 'الرسوم', 'المحصّل', 'المتبقي'],
      rows: out,
      summary: _sum({
        'إجمالي الرسوم': fees,
        'إجمالي المحصّل': paid,
        'إجمالي المتبقي': fees - paid,
      }),
    );
  }

  // ---------------------------------------------------------------- الطلاب

  /// قائمة الطلاب (اختياريًا بحالة محددة أو بدفعة).
  Future<ReportData> studentsList({String? status, int? batchId, String? title}) async {
    final args = <Object?>[];
    final where = <String>['s.deleted_at IS NULL'];
    if (status != null) {
      where.add('s.status = ?');
      args.add(status);
    }
    if (batchId != null) {
      where.add("EXISTS (SELECT 1 FROM enrollments x WHERE x.student_id = s.id "
          "AND x.batch_id = ? AND x.status = 'active')");
      args.add(batchId);
    }
    final rows = await _db.rawQuery('''
      SELECT s.student_no, s.full_name, s.phone, s.guardian_phone, s.status,
        (SELECT group_concat(b.name, '، ') FROM enrollments e
           JOIN batches b ON b.id = e.batch_id
          WHERE e.student_id = s.id AND e.status = 'active') AS batches
      FROM students s WHERE ${where.join(' AND ')}
      ORDER BY s.full_name COLLATE NOCASE''', args);
    return ReportData(
      title: title ?? 'قائمة الطلاب',
      columns: const ['رقم القيد', 'الاسم', 'الهاتف', 'هاتف ولي الأمر', 'الحالة', 'الدفعات'],
      rows: [
        for (final x in rows)
          [
            x['student_no'] as String,
            x['full_name'] as String,
            (x['phone'] as String?) ?? '',
            (x['guardian_phone'] as String?) ?? '',
            studentStatusLabel(x['status'] as String),
            (x['batches'] as String?) ?? '',
          ],
      ],
      summary: _sum({'عدد الطلاب': rows.length}),
    );
  }

  // ----------------------------------------------------------------- الحضور

  Future<ReportData> attendance(int batchId, DateRange r) async {
    final b = await _db.query('batches',
        where: 'id = ?', whereArgs: [batchId], limit: 1);
    if (b.isEmpty) throw const AppException('الدفعة غير موجودة');
    final stats = await _attendance.report(batchId, r.from, r.to);
    var total = 0, good = 0;
    final out = <List<Object>>[];
    for (final s in stats) {
      total += s.total;
      good += s.present + s.late;
      out.add([
        s.name,
        s.present,
        s.absent,
        s.late,
        s.excused,
        s.leave,
        '${(s.rate * 100).round()}%',
      ]);
    }
    final overall = total == 0 ? 0 : (good * 100 / total).round();
    return ReportData(
      title: 'تقرير الحضور: ${b.first['name']}',
      subtitle: '${r.label} • نسبة الحضور = (حاضر + متأخر) ÷ كل الجلسات',
      columns: const ['الطالب', 'حاضر', 'غائب', 'متأخر', 'غائب بعذر', 'إجازة', 'نسبة الحضور'],
      rows: out,
      summary: _sum({'نسبة الحضور العامة': '$overall%', 'عدد الطلاب': out.length}),
    );
  }
}
