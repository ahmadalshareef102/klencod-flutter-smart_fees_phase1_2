import 'package:sqflite/sqflite.dart';

import '../../../core/database/audit_log.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/helpers/dates.dart';
import '../../batches/domain/batch_type.dart';
import '../../fees/data/fee_plan_repository.dart';
import '../../payments/data/payment_repository.dart';

class StudentInput {
  const StudentInput({
    this.studentNo,
    required this.fullName,
    this.gender,
    this.phone,
    this.guardianPhone,
    this.guardianName,
    this.motherName,
    this.birthDate,
    this.address,
    this.notes,
    required this.registeredAt,
  });

  final String? studentNo;
  final String fullName;
  final String? gender; // male | female
  final String? phone;
  final String? guardianPhone;
  final String? guardianName;
  final String? motherName;
  final String? birthDate;
  final String? address;
  final String? notes;
  final String registeredAt;
}

class EnrollInput {
  const EnrollInput({
    required this.batchId,
    required this.fee,
    this.discount = 0,
    this.paidNow = 0,
    this.method = PaymentMethod.cash,
    this.receiverName,
  });

  final int batchId;

  /// الرسوم الأصلية لهذا الطالب (قد تختلف عن رسوم الدفعة الافتراضية).
  final int fee;
  final int discount;
  final int paidNow;
  final PaymentMethod method;
  final String? receiverName;
}

class StudentRow {
  const StudentRow({
    required this.id,
    required this.studentNo,
    required this.fullName,
    required this.phone,
    required this.status,
    required this.fees,
    required this.paid,
    required this.batches,
    required this.archived,
  });

  final int id;
  final String studentNo;
  final String fullName;
  final String? phone;
  final String status;
  final int fees;
  final int paid;
  final String? batches;
  final bool archived;

  int get remaining => fees - paid;
}

class InstallmentView {
  const InstallmentView({
    required this.id,
    required this.seq,
    required this.amount,
    required this.paid,
    required this.dueDate,
    required this.status,
  });

  final int id;
  final int seq;
  final int amount;
  final int paid;
  final String dueDate;
  final String status;
}

class EnrollmentView {
  const EnrollmentView({
    required this.id,
    required this.batchName,
    required this.batchType,
    required this.finalFee,
    required this.paid,
    required this.status,
    required this.installments,
  });

  final int id;
  final String batchName;
  final BatchType batchType;
  final int finalFee;
  final int paid;
  final String status;
  final List<InstallmentView> installments;

  int get remaining => finalFee - paid;
}

class PaymentView {
  const PaymentView({
    required this.id,
    required this.enrollmentId,
    required this.batchName,
    required this.amount,
    required this.paidAt,
    required this.method,
    required this.receiptNo,
    required this.status,
    required this.reversalReason,
  });

  final int id;
  final int enrollmentId;
  final String batchName;
  final int amount;
  final String paidAt;
  final String method;
  final String receiptNo;
  final String status;
  final String? reversalReason;

  bool get isActive => status == 'active';
}

class StudentDetail {
  const StudentDetail({
    required this.student,
    required this.enrollments,
    required this.payments,
  });

  final Map<String, Object?> student;
  final List<EnrollmentView> enrollments;
  final List<PaymentView> payments;

  int get totalFees => enrollments
      .where((e) => e.status != 'cancelled')
      .fold(0, (s, e) => s + e.finalFee);
  int get totalPaid =>
      payments.where((p) => p.isActive).fold(0, (s, p) => s + p.amount);
  int get remaining => totalFees - totalPaid;
}

/// إدارة الطلاب وتسجيلهم في الدفعات.
class StudentRepository {
  StudentRepository(this._db, this._fees, this._payments,
      {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Database _db;
  final FeePlanRepository _fees;
  final PaymentRepository _payments;
  final DateTime Function() _clock;

  static final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// يضيف الطالب، وإن وُجد [enroll] يسجّله في الدفعة وينشئ خطة الأقساط
  /// ويسجّل الدفعة الأولى، كل ذلك في معاملة واحدة تتراجع كاملة عند أي خطأ.
  Future<int> createStudent(StudentInput s, {EnrollInput? enroll}) async {
    _validate(s);
    return _db.transaction((txn) async {
      final no = await _resolveStudentNo(txn, s.studentNo);
      final id = await txn.insert('students', _toRow(s, no));
      await writeAudit(txn,
          entity: 'student',
          entityId: id,
          action: 'create',
          details: {'name': s.fullName.trim(), 'student_no': no});
      if (enroll != null) {
        await _enrollIn(txn, id, s.registeredAt, enroll);
      }
      return id;
    });
  }

  /// تسجيل طالب موجود في دفعة (طالب يلتحق بأكثر من دفعة).
  Future<int> addEnrollment(int studentId, EnrollInput e,
      {String? enrolledAt}) {
    return _db.transaction((txn) async {
      final st = await txn.query('students',
          columns: ['id'],
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [studentId],
          limit: 1);
      if (st.isEmpty) throw const AppException('الطالب غير موجود');
      return _enrollIn(txn, studentId,
          enrolledAt ?? Dates.iso(_clock()), e);
    });
  }

  Future<int> _enrollIn(
      Transaction txn, int studentId, String enrolledAt, EnrollInput e) async {
    if (!_isoDate.hasMatch(enrolledAt)) {
      throw const AppException('تاريخ الانضمام غير صالح');
    }
    final b = await txn.query('batches',
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [e.batchId],
        limit: 1);
    if (b.isEmpty) throw const AppException('الدفعة غير موجودة');
    final batch = b.first;
    if (batch['status'] != 'open') {
      throw const AppException('لا يمكن التسجيل في دفعة مغلقة');
    }
    final type = BatchType.fromCode(batch['batch_type'] as String);

    if (e.fee <= 0) {
      throw const AppException('مبلغ الرسوم يجب أن يكون أكبر من صفر');
    }
    // الخصم لا يُطبَّق على الرسوم المتكررة (تتراكم كل فترة).
    final discount = type.isRecurring ? 0 : e.discount;
    if (discount < 0 || discount >= e.fee) {
      throw const AppException('الخصم يجب أن يكون أقل من مبلغ الرسوم');
    }
    if (e.paidNow < 0) {
      throw const AppException('المبلغ المدفوع لا يمكن أن يكون سالبًا');
    }

    final dup = await txn.query('enrollments',
        columns: ['id'],
        where: "student_id = ? AND batch_id = ? AND status = 'active'",
        whereArgs: [studentId, e.batchId],
        limit: 1);
    if (dup.isNotEmpty) {
      throw const AppException('الطالب مسجّل في هذه الدفعة مسبقًا');
    }

    final finalFee = e.fee - discount;
    final enrollmentId = await txn.insert('enrollments', {
      'student_id': studentId,
      'course_id': batch['course_id'],
      'batch_id': e.batchId,
      'enrolled_at': enrolledAt,
      'original_fee': e.fee,
      'discount': discount,
      'extra_fee': 0,
      'final_fee': finalFee,
    });

    final enrolled = Dates.parse(enrolledAt);
    final start = batch['start_date'] == null
        ? enrolled
        : Dates.parse(batch['start_date'] as String);

    // خطة الأقساط بحسب نوع الدفعة.
    if (type.isRecurring) {
      final p = type.periodMonths!;
      await _fees.createPlanIn(txn,
          enrollmentId: enrollmentId,
          count: 1,
          firstDue: enrolled,
          intervalDays: 30 * p,
          periodMonths: p,
          monthlyFee: finalFee);
    } else if (type == BatchType.monthlyTotal || type == BatchType.fixedCourse) {
      final end = batch['end_date'] == null
          ? enrolled
          : Dates.parse(batch['end_date'] as String);
      var months = Dates.approxMonths(start, end);
      if (months > finalFee) months = finalFee;
      await _fees.createPlanIn(txn,
          enrollmentId: enrollmentId,
          count: months,
          firstDue: enrolled.isBefore(start) ? start : enrolled,
          intervalDays: 30,
          periodMonths: 1);
    } else if (type == BatchType.installments) {
      var n = batch['installments_count'] as int;
      if (n > finalFee) n = finalFee;
      await _fees.createPlanIn(txn,
          enrollmentId: enrollmentId,
          count: n < 1 ? 1 : n,
          firstDue: enrolled,
          intervalDays: batch['interval_days'] as int);
    } else {
      // مخصص: قسط واحد في تاريخ بداية الدفعة.
      await _fees.createPlanIn(txn,
          enrollmentId: enrollmentId,
          count: 1,
          firstDue: start,
          intervalDays: 30);
    }

    await writeAudit(txn,
        entity: 'enrollment',
        entityId: enrollmentId,
        action: 'create',
        details: {
          'student_id': studentId,
          'batch_id': e.batchId,
          'fee': e.fee,
          'discount': discount,
        });

    if (e.paidNow > 0) {
      await _payments.recordPaymentIn(txn,
          enrollmentId: enrollmentId,
          amount: e.paidNow,
          paidAt: Dates.iso(_clock()),
          method: e.method,
          receiverName: e.receiverName);
    }
    return enrollmentId;
  }

  /// تعديل البيانات الشخصية فقط (الرسوم والتسجيلات لا تتأثر).
  Future<void> updateStudent(int id, StudentInput s) async {
    _validate(s);
    await _db.transaction((txn) async {
      final cur = await txn.query('students',
          columns: ['student_no'], where: 'id = ?', whereArgs: [id], limit: 1);
      if (cur.isEmpty) throw const AppException('الطالب غير موجود');
      var no = cur.first['student_no'] as String;
      final wanted = s.studentNo?.trim() ?? '';
      if (wanted.isNotEmpty && wanted != no) {
        final taken = await txn.query('students',
            columns: ['id'],
            where: 'student_no = ? AND id != ?',
            whereArgs: [wanted, id],
            limit: 1);
        if (taken.isNotEmpty) throw const AppException('رقم القيد مستخدم مسبقًا');
        no = wanted;
      }
      final row = _toRow(s, no)
        ..remove('registered_at')
        ..['updated_at'] = DateTime.now().toUtc().toIso8601String();
      await txn.update('students', row, where: 'id = ?', whereArgs: [id]);
      await writeAudit(txn,
          entity: 'student', entityId: id, action: 'update');
    });
  }

  /// أرشفة (حذف ناعم): السجلات المالية تبقى كما هي.
  Future<void> archive(int id) => _setArchived(id, true);
  Future<void> restore(int id) => _setArchived(id, false);

  Future<void> _setArchived(int id, bool archived) async {
    await _db.transaction((txn) async {
      await txn.update(
          'students',
          {
            'deleted_at':
                archived ? DateTime.now().toUtc().toIso8601String() : null,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [id]);
      await writeAudit(txn,
          entity: 'student',
          entityId: id,
          action: archived ? 'archive' : 'restore');
    });
  }

  Future<List<StudentRow>> list({
    String query = '',
    int? batchId,
    bool archived = false,
  }) async {
    final args = <Object?>[];
    final where = <String>[
      archived ? 's.deleted_at IS NOT NULL' : 's.deleted_at IS NULL',
    ];
    final q = query.trim();
    if (q.isNotEmpty) {
      where.add('(s.full_name LIKE ? OR s.student_no LIKE ? OR s.phone LIKE ?)');
      args.addAll(['%$q%', '%$q%', '%$q%']);
    }
    if (batchId != null) {
      where.add('EXISTS (SELECT 1 FROM enrollments x WHERE x.student_id = s.id '
          "AND x.batch_id = ? AND x.status = 'active')");
      args.add(batchId);
    }

    final rows = await _db.rawQuery('''
      SELECT s.id, s.student_no, s.full_name, s.phone, s.status, s.deleted_at,
        (SELECT COALESCE(SUM(e.final_fee), 0) FROM enrollments e
          WHERE e.student_id = s.id AND e.status != 'cancelled') AS fees,
        (SELECT COALESCE(SUM(p.amount), 0) FROM payments p
           JOIN enrollments e2 ON e2.id = p.enrollment_id
          WHERE e2.student_id = s.id AND p.status = 'active') AS paid,
        (SELECT group_concat(b.name, '، ') FROM enrollments e3
           JOIN batches b ON b.id = e3.batch_id
          WHERE e3.student_id = s.id AND e3.status = 'active') AS batches
      FROM students s
      WHERE ${where.join(' AND ')}
      ORDER BY s.full_name COLLATE NOCASE''', args);

    return rows
        .map((r) => StudentRow(
              id: r['id'] as int,
              studentNo: r['student_no'] as String,
              fullName: r['full_name'] as String,
              phone: r['phone'] as String?,
              status: r['status'] as String,
              fees: (r['fees'] as num).toInt(),
              paid: (r['paid'] as num).toInt(),
              batches: r['batches'] as String?,
              archived: r['deleted_at'] != null,
            ))
        .toList();
  }

  Future<StudentDetail?> detail(int id) async {
    final st = await _db.query('students', where: 'id = ?', whereArgs: [id], limit: 1);
    if (st.isEmpty) return null;

    final enrRows = await _db.rawQuery('''
      SELECT e.id, e.final_fee, e.status, COALESCE(b.name, '—') AS batch_name,
             COALESCE(b.batch_type, 'custom') AS batch_type,
        (SELECT COALESCE(SUM(p.amount), 0) FROM payments p
          WHERE p.enrollment_id = e.id AND p.status = 'active') AS paid
      FROM enrollments e LEFT JOIN batches b ON b.id = e.batch_id
      WHERE e.student_id = ? ORDER BY e.id''', [id]);

    final enrollments = <EnrollmentView>[];
    for (final r in enrRows) {
      final inst = await _db.query('installments',
          where: 'enrollment_id = ?',
          whereArgs: [r['id']],
          orderBy: 'seq');
      enrollments.add(EnrollmentView(
        id: r['id'] as int,
        batchName: r['batch_name'] as String,
        batchType: BatchType.fromCode(r['batch_type'] as String),
        finalFee: r['final_fee'] as int,
        paid: (r['paid'] as num).toInt(),
        status: r['status'] as String,
        installments: inst
            .map((i) => InstallmentView(
                  id: i['id'] as int,
                  seq: i['seq'] as int,
                  amount: i['amount'] as int,
                  paid: i['paid_amount'] as int,
                  dueDate: i['due_date'] as String,
                  status: i['status'] as String,
                ))
            .toList(),
      ));
    }

    final payRows = await _db.rawQuery('''
      SELECT p.*, COALESCE(b.name, '—') AS batch_name
      FROM payments p JOIN enrollments e ON e.id = p.enrollment_id
      LEFT JOIN batches b ON b.id = e.batch_id
      WHERE e.student_id = ? ORDER BY p.paid_at DESC, p.id DESC''', [id]);

    return StudentDetail(
      student: st.first,
      enrollments: enrollments,
      payments: payRows
          .map((p) => PaymentView(
                id: p['id'] as int,
                enrollmentId: p['enrollment_id'] as int,
                batchName: p['batch_name'] as String,
                amount: p['amount'] as int,
                paidAt: p['paid_at'] as String,
                method: p['method'] as String,
                receiptNo: p['receipt_no'] as String,
                status: p['status'] as String,
                reversalReason: p['reversal_reason'] as String?,
              ))
          .toList(),
    );
  }

  // ---------------------------------------------------------------- داخلي

  void _validate(StudentInput s) {
    if (s.fullName.trim().isEmpty) throw const AppException('اسم الطالب مطلوب');
    if (!_isoDate.hasMatch(s.registeredAt)) {
      throw const AppException('تاريخ الانضمام غير صالح');
    }
    if (s.gender != null && s.gender != 'male' && s.gender != 'female') {
      throw const AppException('قيمة الجنس غير صالحة');
    }
  }

  Map<String, Object?> _toRow(StudentInput s, String no) => {
        'student_no': no,
        'full_name': s.fullName.trim(),
        'gender': s.gender,
        'phone': _n(s.phone),
        'guardian_phone': _n(s.guardianPhone),
        'guardian_name': _n(s.guardianName),
        'mother_name': _n(s.motherName),
        'birth_date': _n(s.birthDate),
        'address': _n(s.address),
        'notes': _n(s.notes),
        'registered_at': s.registeredAt,
      };

  Future<String> _resolveStudentNo(Transaction txn, String? provided) async {
    final p = provided?.trim() ?? '';
    if (p.isNotEmpty) {
      final taken = await txn.query('students',
          columns: ['id'], where: 'student_no = ?', whereArgs: [p], limit: 1);
      if (taken.isNotEmpty) throw const AppException('رقم القيد مستخدم مسبقًا');
      return p;
    }
    // توليد: أكبر رقم عددي موجود + 1، مع التأكد من عدم التكرار.
    final r = await txn.rawQuery(
        'SELECT COALESCE(MAX(CAST(student_no AS INTEGER)), 0) AS m FROM students');
    var next = (r.first['m'] as num).toInt() + 1;
    while (true) {
      final c = '$next';
      final t = await txn.query('students',
          columns: ['id'], where: 'student_no = ?', whereArgs: [c], limit: 1);
      if (t.isEmpty) return c;
      next++;
    }
  }

  static String? _n(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}
