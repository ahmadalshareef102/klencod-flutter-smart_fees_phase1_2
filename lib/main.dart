import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/database/app_database.dart';
import 'features/installments/data/accrual_service.dart';
import 'features/settings/data/settings_repository.dart';
import 'shared/providers/core_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final database = await AppDatabase.open();
  final themeMode = await SettingsRepository(database.db).getThemeMode();

  // احتساب الرسوم المتكررة المستحقة وتحديث حالات الأقساط عند الإقلاع.
  // فشلها لا يمنع فتح التطبيق (تُعاد المحاولة عند فتح لوحة القيادة).
  try {
    await AccrualService(database.db).run();
  } catch (_) {}

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        initialThemeModeProvider.overrideWithValue(themeMode),
      ],
      child: const SmartFeesApp(),
    ),
  );
}