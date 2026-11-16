import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/providers/core_providers.dart';

/// قسم "المزيد": المظهر يعمل فعليًا الآن؛ بقية الأقسام تظهر معطّلة
/// مع رقم المرحلة التي ستُفعَّل فيها (لا أزرار تبدو فعّالة وهي ليست كذلك).
class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  static const _upcoming = <(String, IconData, int)>[
    ('الدورات والدفعات', Icons.school_outlined, 3),
    ('الأقساط', Icons.event_note_outlined, 4),
    ('التذكيرات', Icons.notifications_outlined, 7),
    ('المصروفات', Icons.receipt_long_outlined, 4),
    ('التقارير', Icons.bar_chart_outlined, 6),
    ('إعدادات المعهد', Icons.apartment_outlined, 3),
    ('النسخ الاحتياطي', Icons.backup_outlined, 8),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('المزيد')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('المظهر', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('فاتح')),
              ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('داكن')),
              ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('تلقائي')),
            ],
            selected: {mode},
            onSelectionChanged: (s) =>
                ref.read(themeModeProvider.notifier).setMode(s.first),
          ),
          const SizedBox(height: 24),
          for (final item in _upcoming)
            ListTile(
              enabled: false,
              leading: Icon(item.$2),
              title: Text(item.$1),
              subtitle: Text('المرحلة ${item.$3}'),
            ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('حول التطبيق'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: '${AppConstants.appNameEn} - ${AppConstants.appNameAr}',
              applicationVersion: AppConstants.appVersion,
              children: const [
                Text('نظام إدارة رسوم الطلاب والمعاهد. يعمل دون إنترنت.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
