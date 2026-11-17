import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/ui_helpers.dart';
import '../../../shared/providers/core_providers.dart';
import '../data/dashboard_repository.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الرسوم')),
      body: stats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(errorText(e), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: () => ref.invalidate(dashboardStatsProvider),
                  child: const Text('إعادة المحاولة')),
            ]),
          ),
        ),
        data: (s) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(dashboardStatsProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              _FeesSummary(s),
              const SectionTitle('نظرة عامة'),
              _Overview(s),
              const SectionTitle('إجراء سريع'),
              const _QuickActions(),
            ],
          ),
        ),
      ),
    );
  }
}

/// بطاقات الإجمالي / المستلم / المستحق مع نسبة دائرية.
class _FeesSummary extends StatelessWidget {
  const _FeesSummary(this.s);

  final DashboardStats s;

  @override
  Widget build(BuildContext context) {
    final total = s.totalFees;
    double ratio(int v) => total <= 0 ? 0 : (v / total).clamp(0.0, 1.0);
    final due = s.remaining < 0 ? 0 : s.remaining;
    return Row(
      children: [
        Expanded(
            child: _SummaryTile(
                title: 'الإجمالي',
                amount: s.totalFees,
                ratio: total > 0 ? 1 : 0,
                color: Theme.of(context).colorScheme.primary)),
        const SizedBox(width: 10),
        Expanded(
            child: _SummaryTile(
                title: 'المستلم',
                amount: s.collected,
                ratio: ratio(s.collected),
                color: AppColors.success)),
        const SizedBox(width: 10),
        Expanded(
            child: _SummaryTile(
                title: 'مستحق',
                amount: due,
                ratio: ratio(due),
                color: AppColors.danger)),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.title,
    required this.amount,
    required this.ratio,
    required this.color,
  });

  final String title;
  final int amount;
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: Column(
        children: [
          Text(title,
              style: t.titleSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: ratio,
                    strokeWidth: 6,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.15),
                  ),
                ),
                Text('${(ratio * 100).round()}%', style: t.labelLarge),
              ],
            ),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(yer(amount),
                style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview(this.s);

  final DashboardStats s;

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String, Color?, String?)>[
      (Icons.menu_book_rounded, 'إجمالي الدفعات', '${s.batches}', null, null),
      (Icons.groups_rounded, 'إجمالي الطلاب', '${s.students}', null, '/students'),
      (Icons.schedule_rounded, 'انضم حديثًا', '${s.recentStudents}', null, null),
      (Icons.account_balance_wallet_rounded, 'تحصيل اليوم',
          yer(s.collectedToday), AppColors.success, '/reports'),
      (Icons.payments_rounded, 'مصروف اليوم', yer(s.expensesToday),
          AppColors.danger, '/expenses'),
      (Icons.warning_amber_rounded, 'طلاب متأخرون', '${s.lateStudents}',
          s.lateStudents > 0 ? AppColors.danger : null, '/reports'),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.95,
      children: [
        for (final i in items) _StatTile(i.$1, i.$2, i.$3, i.$4,
            i.$5 == null ? null : () => context.push(i.$5!)),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(this.icon, this.label, this.value, this.valueColor, this.onTap);

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon, size: 40),
          const Spacer(),
          Text(label,
              style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: t.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: valueColor ?? Theme.of(context).colorScheme.primary)),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    Widget action(IconData icon, String label, VoidCallback onTap) => Expanded(
          child: AppCard(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            onTap: onTap,
            child: Column(children: [
              IconBadge(icon),
              const SizedBox(height: 8),
              Text(label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        );

    return Column(
      children: [
        Row(children: [
          action(Icons.add_business_rounded, 'إضافة دفعة',
              () => context.push('/batches/new')),
          const SizedBox(width: 10),
          action(Icons.person_add_alt_1_rounded, 'إضافة طالب',
              () => context.push('/students/new')),
          const SizedBox(width: 10),
          action(Icons.groups_rounded, 'جميع الطلاب',
              () => context.push('/students')),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          action(Icons.fact_check_rounded, 'الحضور',
              () => context.push('/attendance')),
          const SizedBox(width: 10),
          action(Icons.account_balance_wallet_rounded, 'المصاريف',
              () => context.push('/expenses')),
          const SizedBox(width: 10),
          action(Icons.assessment_rounded, 'التقارير',
              () => context.push('/reports')),
        ]),
      ],
    );
  }
}
