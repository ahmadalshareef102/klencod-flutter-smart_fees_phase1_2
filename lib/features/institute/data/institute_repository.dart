import 'package:sqflite/sqflite.dart';

import '../../../core/database/audit_log.dart';
import '../../../core/errors/app_exception.dart';

class InstituteInfo {
  const InstituteInfo({
    required this.name,
    this.managerName,
    this.phone,
    this.address,
    this.email,
    this.academicYear,
  });

  final String name;
  final String? managerName;
  final String? phone;
  final String? address;
  final String? email;
  final String? academicYear;
}

/// بيانات المعهد (صف واحد). تعديلها لا يغيّر السجلات المالية التاريخية،
/// لأن السندات القديمة تُطبع ببيانات المعهد الحالية فقط عند إعادة الطباعة.
class InstituteRepository {
  InstituteRepository(this._db);

  final Database _db;

  Future<InstituteInfo?> get() async {
    final r = await _db.query('institutes', orderBy: 'id', limit: 1);
    if (r.isEmpty) return null;
    final x = r.first;
    return InstituteInfo(
      name: x['name'] as String,
      managerName: x['manager_name'] as String?,
      phone: x['phone'] as String?,
      address: x['address'] as String?,
      email: x['email'] as String?,
      academicYear: x['academic_year'] as String?,
    );
  }

  Future<void> save(InstituteInfo i) async {
    if (i.name.trim().isEmpty) throw const AppException('اسم المعهد مطلوب');
    final row = <String, Object?>{
      'name': i.name.trim(),
      'manager_name': _n(i.managerName),
      'phone': _n(i.phone),
      'address': _n(i.address),
      'email': _n(i.email),
      'academic_year': _n(i.academicYear),
    };
    await _db.transaction((txn) async {
      final cur = await txn.query('institutes',
          columns: ['id'], orderBy: 'id', limit: 1);
      int id;
      if (cur.isEmpty) {
        id = await txn.insert('institutes', row);
      } else {
        id = cur.first['id'] as int;
        await txn.update(
            'institutes',
            {...row, 'updated_at': DateTime.now().toUtc().toIso8601String()},
            where: 'id = ?',
            whereArgs: [id]);
      }
      await writeAudit(txn,
          entity: 'institute', entityId: id, action: 'save');
    });
  }

  static String? _n(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}
