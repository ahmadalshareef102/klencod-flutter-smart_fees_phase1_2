import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_constants.dart';

/// قراءة/كتابة الإعدادات المحلية من جدول app_settings.
class SettingsRepository {
  SettingsRepository(this._db);

  final Database _db;

  Future<String?> getString(String key) async {
    final r = await _db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> setString(String key, String value) async {
    await _db.insert(
      'app_settings',
      {
        'key': key,
        'value': value,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ThemeMode> getThemeMode() async {
    switch (await getString(AppConstants.settingThemeMode)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) =>
      setString(AppConstants.settingThemeMode, mode.name);
}
