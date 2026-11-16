import 'package:sqflite/sqflite.dart';

import 'tables/schema_v1.dart';

/// إدارة ترقيات المخطط. لإضافة إصدار جديد: أضف مدخلًا في [steps] ثم ارفع
/// [AppDatabase.schemaVersion]. كل خطوة تُنفَّذ داخل معاملة sqflite.
class DatabaseMigrations {
  DatabaseMigrations._();

  static const Map<int, List<String>> steps = {
    1: schemaV1,
  };

  static Future<void> onCreate(Database db, int version) =>
      _apply(db, 1, version);

  static Future<void> onUpgrade(Database db, int oldVersion, int newVersion) =>
      _apply(db, oldVersion + 1, newVersion);

  static Future<void> _apply(Database db, int from, int to) async {
    for (var v = from; v <= to; v++) {
      final statements = steps[v];
      if (statements == null) {
        throw StateError('لا توجد خطوة ترحيل للإصدار $v');
      }
      for (final sql in statements) {
        await db.execute(sql);
      }
    }
  }
}
