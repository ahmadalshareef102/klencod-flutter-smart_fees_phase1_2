import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'database_migrations.dart';

/// غلاف لاتصال SQLite الوحيد في التطبيق.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const int schemaVersion = 1;
  static const String fileName = 'smart_fees.db';

  /// فتح القاعدة الحقيقية على الجهاز.
  static Future<AppDatabase> open() async {
    final path = p.join(await getDatabasesPath(), fileName);
    return openWith(databaseFactory, path);
  }

  /// فتح القاعدة بمصنع محدد (يُستخدم في الاختبارات مع sqflite_common_ffi).
  static Future<AppDatabase> openWith(DatabaseFactory factory, String path) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: configure,
        onCreate: DatabaseMigrations.onCreate,
        onUpgrade: DatabaseMigrations.onUpgrade,
      ),
    );
    return AppDatabase._(db);
  }

  /// يُفعّل المفاتيح الأجنبية عند كل اتصال.
  static Future<void> configure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> close() => db.close();
}
