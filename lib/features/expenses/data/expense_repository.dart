import 'package:sqflite/sqflite.dart';

import '../../../core/database/audit_log.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/helpers/date_range.dart';
import '../../payments/data/payment_repository.dart';

class ExpenseCategory {
  const ExpenseCategory(this.id, this.name);

  final int id;
  final String name;
}

class ExpenseInput {
  const ExpenseInput({
    required this.categoryId,
    required this.amount,
    required this.spentAt,
    this.description,
    this.method = PaymentMethod.cash,
    this.notes,
  });

  final int categoryId;
  final int amount;
  final String spentAt;
  final String? description;
  final PaymentMethod method;
  final String? notes;
}

class ExpenseRow {
  const ExpenseRow({
    required this.id,
    required this.categoryName,
    required this.amount,
    required this.spentAt,
    required this.description,
    required this.method,
    required this.notes,
  });

  final int id;
  final String categoryName;
  final int amount;
  final String spentAt;
  final String? description;
  final String method;
  final String? notes;
}

class ExpenseSummary {
  const ExpenseSummary({
    required this.rows,
    required this.total,
    required this.byCategory,
  });

  final List<ExpenseRow> rows;
  final int total;

  /// إجمالي كل تصنيف (الأكبر أولًا).
  final List<MapEntry<String, int>> byCategory;
}

/// مصروفات المعهد. لا حذف نهائي: الإلغاء يُخفي المصروف ويُسجَّل في التدقيق.
class ExpenseRepository {
  ExpenseRepository(this._db);

  final Database _db;

  static final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  Future<List<ExpenseCategory>> categories() async {
    final rows = await _db.query('expense_categories',
        where: 'deleted_at IS NULL', orderBy: 'id');
    return rows
        .map((r) => ExpenseCategory(r['id'] as int, r['name'] as String))
        .toList();
  }

  Future<int> addCategory(String name) async {
    final n = name.trim();
    if (n.isEmpty) throw const AppException('اسم التصنيف مطلوب');
    final dup = await _db.query('expense_categories',
        columns: ['id'],
        where: 'lower(name) = lower(?) AND deleted_at IS NULL',
        whereArgs: [n],
        limit: 1);
    if (dup.isNotEmpty) throw const AppException('التصنيف موجود مسبقًا');
    return _db.insert('expense_categories', {'name': n});
  }

  Future<int> add(ExpenseInput i) async {
    if (i.amount <= 0) {
      throw const AppException('المبلغ يجب أن يكون أكبر من صفر');
    }
    if (!_isoDate.hasMatch(i.spentAt)) {
      throw const AppException('تاريخ المصروف غير صالح');
    }
    return _db.transaction((txn) async {
      final cat = await txn.query('expense_categories',
          columns: ['id'],
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [i.categoryId],
          limit: 1);
      if (cat.isEmpty) throw const AppException('نوع المصروف غير صالح');
      final id = await txn.insert('expenses', {
        'category_id': i.categoryId,
        'amount': i.amount,
        'spent_at': i.spentAt,
        'description': _n(i.description),
        'method': i.method.code,
        'notes': _n(i.notes),
      });
      await writeAudit(txn,
          entity: 'expense',
          entityId: id,
          action: 'create',
          details: {'amount': i.amount, 'category_id': i.categoryId});
      return id;
    });
  }

  /// إلغاء مصروف (حذف ناعم مع أثر في التدقيق).
  Future<void> cancel(int id, {String? reason}) async {
    await _db.transaction((txn) async {
      final r = await txn.query('expenses',
          where: 'id = ? AND deleted_at IS NULL', whereArgs: [id], limit: 1);
      if (r.isEmpty) throw const AppException('المصروف غير موجود');
      final now = DateTime.now().toUtc().toIso8601String();
      await txn.update('expenses', {'deleted_at': now, 'updated_at': now},
          where: 'id = ?', whereArgs: [id]);
      await writeAudit(txn,
          entity: 'expense',
          entityId: id,
          action: 'cancel',
          details: {'amount': r.first['amount'], 'reason': _n(reason)});
    });
  }

  Future<ExpenseSummary> summary(DateRange range) async {
    final rows = await _db.rawQuery('''
      SELECT x.id, x.amount, x.spent_at, x.description, x.method, x.notes,
             c.name AS category_name
      FROM expenses x JOIN expense_categories c ON c.id = x.category_id
      WHERE x.deleted_at IS NULL AND x.spent_at BETWEEN ? AND ?
      ORDER BY x.spent_at DESC, x.id DESC''', [range.from, range.to]);

    final list = rows
        .map((r) => ExpenseRow(
              id: r['id'] as int,
              categoryName: r['category_name'] as String,
              amount: r['amount'] as int,
              spentAt: r['spent_at'] as String,
              description: r['description'] as String?,
              method: r['method'] as String,
              notes: r['notes'] as String?,
            ))
        .toList();

    final totals = <String, int>{};
    var total = 0;
    for (final e in list) {
      total += e.amount;
      totals[e.categoryName] = (totals[e.categoryName] ?? 0) + e.amount;
    }
    final by = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ExpenseSummary(rows: list, total: total, byCategory: by);
  }

  static String? _n(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}
