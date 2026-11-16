import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../features/fees/data/fee_plan_repository.dart';
import '../../features/payments/data/payment_repository.dart';
import '../../features/settings/data/settings_repository.dart';

/// يُستبدل في main.dart بعد فتح القاعدة.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('يجب تجاوز appDatabaseProvider في main'),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(appDatabaseProvider).db),
);

final paymentRepositoryProvider = Provider<PaymentRepository>(
  (ref) => PaymentRepository(ref.watch(appDatabaseProvider).db),
);

final feePlanRepositoryProvider = Provider<FeePlanRepository>(
  (ref) => FeePlanRepository(ref.watch(appDatabaseProvider).db),
);

/// وضع الثيم المحفوظ وقت الإقلاع (يُستبدل في main).
final initialThemeModeProvider = Provider<ThemeMode>((ref) => ThemeMode.system);

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.watch(initialThemeModeProvider);

  /// يغيّر الوضع فورًا ثم يحفظه محليًا.
  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await ref.read(settingsRepositoryProvider).setThemeMode(mode);
  }
}
