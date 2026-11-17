import 'package:sqflite/sqflite.dart';

import '../../../core/database/audit_log.dart';
import '../../../core/errors/app_exception.dart';
import '../domain/batch_type.dart';

class BatchInput {
  const BatchInput({
    required this.name,
    required this.type,
    required this.fee,
    required this.startDate,
    this.endDate,
    this.subject,
    this.daysCount = 0,
    this.installmentsCount = 1,
    this.intervalDays = 30,
    this.trainer,
  });

  final String name;
  final BatchType type;
  final int fee;
  final String startDate;
  final String? endDate;
  final String? subject;
  final int daysCount;
  final int installmentsCount;
  final int intervalDays;
  final String? trainer;
}

class BatchSummary {
  const BatchSummary({
    required this.id,
    required this.name,
    required this.type,
    required this.fee,
    required this.startDate,
    required this.endDate,
    required this.subject,
    required this.status,
    required this.studentCount,
    required this.installmentsCount,
    required this.intervalDays,
  });

  final int id;
  final String name;
  final BatchType type;
  final int fee;
  final String? startDate;
  final String? endDate;
  final String? subject;
  final String status;
  final int studentCount;
  final int installmentsCount;
  final int intervalDays;

  factory BatchSummary.fromRow(Map<String, Object?> r) => BatchSummary(
        id: r['id'] as int,
        name: r['name'] as String,
        type: BatchType.fromCode(r['batch_type'] as String),
        fee: r['fee_amount'] as int,
        startDate: r['start_date'] as String?,
        endDate: r['end_date'] as String?,
        subject: r['subject'] as String?,
        status: r['status'] as String,
        studentCount: (r['student_count'] as num?)?.toInt() ?? 0,
        installmentsCount: r['installments_count'] as int,
        intervalDays: r['interval_days'] as int,
      );
}

/// إدارة الدفعات.
class BatchRepository {
  BatchRepository(this._db);

  final Database _db;

  static final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  Future<int> create(BatchInput i) async {
    final name = i.name.trim();
    if (name.isEmpty) throw const AppException('اسم الدفعة مطلوب');
    if (i.fee <= 0) throw const AppException('مبلغ الرسوم يجب أن يكون أكبر من صفر');
    if (!_isoDate.hasMatch(i.startDate)) {
      throw const AppException('تاريخ البدء مطلوب');
    }
    if (i.type.needsEndDate && i.endDate == null) {
      throw const AppException('تاريخ الانتهاء مطلوب لهذا النوع من الدفعات');
    }
    if (i.endDate != null && i.endDate!.compareTo(i.startDate) < 0) {
      throw const AppException('تاريخ الانتهاء يجب أن يكون بعد تاريخ البدء');
    }
    if (i.type == BatchType.installments && i.installmentsCount < 2) {
      throw const AppException('عدد الأقساط يجب أن يكون 2 على الأقل');
    }
    if (i.intervalDays < 1) {
      throw const AppException('الفاصل بين الأقساط يجب أن يكون يومًا على الأقل');
    }

    final dup = await _db.query('batches',
        columns: ['id'],
        where: 'lower(name) = lower(?) AND deleted_at IS NULL',
        whereArgs: [name],
        limit: 1);
    if (dup.isNotEmpty) throw const AppException('توجد دفعة بنفس الاسم');

    return _db.transaction((txn) async {
      final id = await txn.insert('batches', {
        'name': name,
        'batch_type': i.type.code,
        'fee_amount': i.fee,
        'subject': _nullIfBlank(i.subject),
        'days_count': i.daysCount,
        'installments_count': i.type == BatchType.installments ? i.installmentsCount : 1,
        'interval_days': i.intervalDays,
        'trainer': _nullIfBlank(i.trainer),
        'start_date': i.startDate,
        'end_date': i.endDate,
      });
      await writeAudit(txn,
          entity: 'batch',
          entityId: id,
          action: 'create',
          details: {'name': name, 'type': i.type.code, 'fee': i.fee});
      return id;
    });
  }

  Future<List<BatchSummary>> list({bool includeArchived = false}) async {
    final rows = await _db.rawQuery('''
      SELECT b.*,
        (SELECT COUNT(*) FROM enrollments e
           JOIN students s ON s.id = e.student_id
          WHERE e.batch_id = b.id AND e.status = 'active'
            AND s.deleted_at IS NULL) AS student_count
      FROM batches b
      WHERE b.deleted_at IS NULL ${includeArchived ? '' : "AND b.status != 'archived'"}
      ORDER BY b.created_at DESC, b.id DESC''');
    return rows.map(BatchSummary.fromRow).toList();
  }

  Future<BatchSummary?> get(int id) async {
    final rows = await _db.rawQuery('''
      SELECT b.*, 0 AS student_count FROM batches b WHERE b.id = ?''', [id]);
    return rows.isEmpty ? null : BatchSummary.fromRow(rows.first);
  }

  /// فتح/إغلاق/أرشفة. لا حذف نهائي.
  Future<void> setStatus(int id, String status) async {
    if (!const {'open', 'closed', 'archived'}.contains(status)) {
      throw const AppException('حالة غير صالحة');
    }
    await _db.transaction((txn) async {
      await txn.update(
          'batches',
          {
            'status': status,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [id]);
      await writeAudit(txn,
          entity: 'batch', entityId: id, action: 'status', details: {'status': status});
    });
  }

  static String? _nullIfBlank(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}
