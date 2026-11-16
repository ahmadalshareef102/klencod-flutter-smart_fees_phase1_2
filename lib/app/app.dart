import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_constants.dart';
import '../shared/providers/core_providers.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class SmartFeesApp extends ConsumerStatefulWidget {
  const SmartFeesApp({super.key});

  @override
  ConsumerState<SmartFeesApp> createState() => _SmartFeesAppState();
}

class _SmartFeesAppState extends ConsumerState<SmartFeesApp> {
  // يُنشأ مرة واحدة حتى لا تضيع حالة التنقل عند إعادة البناء.
  late final GoRouter _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: AppConstants.appNameEn,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      // لغة عربية فقط => اتجاه RTL تلقائيًا في كل الواجهات.
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: _router,
    );
  }
}
