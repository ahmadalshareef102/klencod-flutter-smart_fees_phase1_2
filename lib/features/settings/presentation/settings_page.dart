import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/app_card.dart';
import '../../../shared/providers/core_providers.dart';

/// شاشة الإعدادات: شبكة أقسام. العناصر غير المنفَّذة بعد تظهر معطّلة
/// مع «قريبًا» حتى لا يوجد زر يبدو فعّالًا وهو ليس كذلك.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final modeLabel = switch (mode) {
      ThemeMode.light => 'الوضع الفاتح',
      ThemeMode.dark => 'الوضع الداكن',
      ThemeMode.system => 'تلقائي',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          _Section('المعهد', [
            _Item(Icons.groups_rounded, 'جميع الطلاب',
                onTap: () => context.push('/students')),
            _Item(Icons.apartment_rounded, 'إعدادات المعهد',
                onTap: () => context.push('/institute')),
            const _Item(Icons.cloud_upload_rounded, 'نسخ احتياطي'),
          ]),
          _Section('الإدارة', [
            _Item(Icons.account_balance_wallet_rounded, 'المصاريف',
                onTap: () => context.push('/expenses')),
            _Item(Icons.fact_check_rounded, 'الحضور',
                onTap: () => context.push('/attendance')),
            _Item(Icons.attach_file_rounded, 'التقارير',
                onTap: () => context.push('/reports')),
          ]),
          _Section('التطبيق', [
            _Item(Icons.brightness_6_rounded, modeLabel,
                onTap: () => _pickTheme(context, ref, mode)),
            const _Item(Icons.notifications_rounded, 'التذكيرات'),
            const _Item(Icons.lock_rounded, 'قفل التطبيق'),
          ]),
          _Section('مساعدة وحول', [
            _Item(Icons.info_outline_rounded, 'حول التطبيق',
                onTap: () => showAboutDialog(
                      context: context,
                      applicationName:
                          '${AppConstants.appNameEn} – ${AppConstants.appNameAr}',
                      applicationVersion: AppConstants.appVersion,
                      children: const [
                        Text('نظام إدارة رسوم الطلاب والمعاهد. يعمل دون إنترنت وتُحفظ بياناته على هذا الجهاز.'),
                      ],
                    )),
          ]),
          const SizedBox(height: 16),
          Center(
            child: Text('${AppConstants.appNameEn} v${AppConstants.appVersion}',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTheme(
      BuildContext context, WidgetRef ref, ThemeMode current) async {
    final picked = await showModalBottomSheet<ThemeMode>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (m, label, icon) in const [
            (ThemeMode.light, 'الوضع الفاتح', Icons.light_mode_outlined),
            (ThemeMode.dark, 'الوضع الداكن', Icons.dark_mode_outlined),
            (ThemeMode.system, 'تلقائي حسب النظام', Icons.brightness_auto_outlined),
          ])
            ListTile(
              leading: Icon(icon),
              title: Text(label),
              selected: m == current,
              trailing: m == current ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(c, m),
            ),
        ]),
      ),
    );
    if (picked != null) {
      await ref.read(themeModeProvider.notifier).setMode(picked);
    }
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.items);

  final String title;
  final List<_Item> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
          child: Text(title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                  fontWeight: FontWeight.w700)),
        ),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.95,
          children: items,
        ),
      ],
    );
  }
}

class _Item extends StatelessWidget {
  const _Item(this.icon, this.label, {this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconBadge(icon),
            const SizedBox(height: 8),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.bodySmall),
            if (!enabled) Text('قريبًا', style: t.labelSmall),
          ],
        ),
      ),
    );
  }
}
