import 'package:sqflite/sqflite.dart';

import '../../../core/database/audit_log.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/helpers/dates.dart';

enum AttendanceStatus {
  present('present', 'حاضر'),
  absent('absent', 'غائب'),
  late('late', 'متأخر'),
  excused('excused', 'غائب بعذر'),
  leave('leave', 'إجازة');

  const AttendanceStatus(this.code, this.label);

  final String code;
  final String label;

  static AttendanceStatus? fromCode(String? c) {
    for (final s in values) {
      if (s.code == c) return s;
    }
    return null;
  }
}

class RosterEntry {
  const RosterEntry({
    required this.enrollmentId,
    required this.studentNo,
    required this.name,
    required this.status,
    required this.notes,
  });

  final int enrollmentId;
  final String studentNo;
  final String name;
  final AttendanceStatus? status;
  final String? notes;
}

class AttendanceSaveItem {
  const AttendanceSaveItem(this.enrollmentId, this.status, {this.notes});

  final int enrollmentId;
  final AttendanceStatus status;
  final String? notes;
}

class AttendanceStat {
  const AttendanceStat({
    required this.name,
    required this.studentNo,
    required this.present,
    required this.absent,
    required this.late,
    required this.excused,
    required this.leave,
  });

  final String name;
  final String studentNo;
  final int present;
  final int absent;
  final int late;
  final int excused;
  final int leave;

  int get total => present + absent + late + excused + leave;

  /// نسبة الحضور = (حاضر + متأخر) ÷ كل الجلسات المسجَّلة.
  /// الغائب بعذر والإجازة يُعرضان منفصلين ولا يُحسبان حضورًا.
  double get rate => total == 0 ? 0 : (present + late) / total;
}

/// الحضور والغياب. منع التكرار مضمون بقيد UNIQUE (تسجيل + تاريخ + جلسة).
class AttendanceRepository {
  AttendanceRepository(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Database _db;
  final DateTime Function() _clock;

  static final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// طلاب الدفعة النشطون مع حالتهم المسجّلة في التاريخ والجلسة (إن وُجدت).
  Future<List<RosterEntry>> roster(int batchId, String date,
      {int session = 1}) async {
    final rows = await _db.rawQuery('''
      SELECT e.id AS enrollment_id, s.student_no, s.full_name,
             a.status AS att_status, a.notes AS att_notes
      FROM enrollments e
      JOIN students s ON s.id = e.student_id
      LEFT JOIN attendance a
        ON a.enrollment_id = e.id AND a.date = ? AND a.session = ?
      WHERE e.batch_id = ? AND e.status = 'active'
        AND s.status = 'active' AND s.deleted_at IS NULL
      ORDER BY s.full_name COLLATE NOCASE''', [date, session, batchId]);
    return rows
        .map((r) => RosterEntry(
              enrollmentId: r['enrollment_id'] as int,
              studentNo: r['student_no'] as String,
              name: r['full_name'] as String,
              status: AttendanceStatus.fromCode(r['att_status'] as String?),
              notes: r['att_notes'] as String?,
            ))
        .toList();
  }

  /// يحفظ كشف الحضور. السجل الجديد يُدرج، والموجود يُعدَّل مع تسجيل
  /// القيمة القديمة والجديدة في سجل التدقيق. يعيد عدد السجلات المتغيّرة.
  Future<int> save(
    int batchId,
    String date,
    List<AttendanceSaveItem> items, {
    int session = 1,
  }) async {
    if (!_isoDate.hasMatch(date)) throw const AppException('التاريخ غير صالح');
    if (date.compareTo(Dates.iso(_clock())) > 0) {
      throw const AppException('لا يمكن تسجيل حضور بتاريخ مستقبلي');
    }
    if (session < 1) throw const AppException('رقم الجلسة غير صالح');
    if (items.isEmpty) throw const AppException('لم تحدد حالة أي طالب');

    return _db.transaction((txn) async {
      var changed = 0;
      final now = _clock().toUtc().toIso8601String();
      for (final it in items) {
        final enr = await txn.query('enrollments',
            columns: ['id'],
            where: "id = ? AND batch_id = ? AND status = 'active'",
            whereArgs: [it.enrollmentId, batchId],
            limit: 1);
        if (enr.isEmpty) {
          throw const AppException('طالب غير مسجّل في هذه الدفعة');
        }
        final note = (it.notes?.trim().isEmpty ?? true) ? null : it.notes!.trim();
        final ex = await txn.query('attendance',
            where: 'enrollment_id = ? AND date = ? AND session = ?',
            whereArgs: [it.enrollmentId, date, session],
            limit: 1);
        if (ex.isEmpty) {
          final id = await txn.insert('attendance', {
            'enrollment_id': it.enrollmentId,
            'batch_id': batchId,
            'date': date,
            'session': session,
            'status': it.status.code,
            'notes': note,
          });
          await writeAudit(txn,
              entity: 'attendance',
              entityId: id,
              action: 'create',
              details: {'date': date, 'status': it.status.code});
          changed++;
        } else {
          final old = ex.first;
          if (old['status'] == it.status.code && old['notes'] == note) {
            continue; // لا تغيير
          }
          await txn.update(
              'attendance',
              {'status': it.status.code, 'notes': note, 'updated_at': now},
              where: 'id = ?',
              whereArgs: [old['id']]);
          await writeAudit(txn,
              entity: 'attendance',
              entityId: old['id'] as int,
              action: 'update',
              details: {
                'date': date,
                'old_status': old['status'],
                'new_status': it.status.code,
              });
          changed++;
        }
      }
      return changed;
    });
  }

  /// إحصائيات حضور طلاب دفعة في فترة (الأكثر غيابًا أولًا).
  Future<List<AttendanceStat>> report(
      int batchId, String from, String to) async {
    final rows = await _db.rawQuery('''
      SELECT s.full_name, s.student_no,
        COALESCE(SUM(a.status = 'present'), 0) AS p,
        COALESCE(SUM(a.status = 'absent'), 0) AS ab,
        COALESCE(SUM(a.status = 'late'), 0) AS l,
        COALESCE(SUM(a.status = 'excused'), 0) AS ex,
        COALESCE(SUM(a.status = 'leave'), 0) AS lv
      FROM enrollments e
      JOIN students s ON s.id = e.student_id
      LEFT JOIN attendance a
        ON a.enrollment_id = e.id AND a.date BETWEEN ? AND ?
      WHERE e.batch_id = ? AND e.status = 'active' AND s.deleted_at IS NULL
      GROUP BY e.id
      ORDER BY ab DESC, s.full_name COLLATE NOCASE''', [from, to, batchId]);
    return rows
        .map((r) => AttendanceStat(
              name: r['full_name'] as String,
              studentNo: r['student_no'] as String,
              present: (r['p'] as num).toInt(),
              absent: (r['ab'] as num).toInt(),
              late: (r['l'] as num).toInt(),
              excused: (r['ex'] as num).toInt(),
              leave: (r['lv'] as num).toInt(),
            ))
        .toList();
  }
}
