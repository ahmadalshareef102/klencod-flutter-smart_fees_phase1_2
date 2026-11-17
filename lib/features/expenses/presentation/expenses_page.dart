import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/helpers/date_range.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/ui_helpers.dart';
import '../../../shared/providers/core_providers.dart';
import '../data/expense_repository.dart';

class ExpensesPage extends ConsumerStatefulWidget {
  const ExpensesPage({super.key});

  @override
  ConsumerState<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends ConsumerState<ExpensesPage> {
  int _preset = 1; // 0 اليوم، 1 هذا الشهر، 2 الكل

  DateRange get _range {
    final now = DateTime.now();
    return switch (_preset) {
      0 => DateRange.today(now),
      1 => DateRange.month(now),
      _ => DateRange.all,
    };
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(expensesProvider(_range));
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('المصروفات')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/expenses/new'),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('اليوم')),
                ButtonSegment(value: 1, label: Text('هذا الشهر')),
                ButtonSegment(value: 2, label: Text('الكل')),
              ],
              selected: {_preset},
              onSelectionChanged: (s) => setState(() => _preset = s.first),
            ),
          ),
          Expanded(
            child: summary.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(errorText(e))),
              data: (s) {
                if (s.rows.isEmpty) {
                  return const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'لا توجد مصروفات في هذه الفترة',
                    message: 'اضغط + لتسجيل أول مصروف.',
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                  children: [
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('إجمالي المصروفات', style: t.bodySmall),
                          const SizedBox(height: 4),
                          Text(yer(s.total),
                              style: t.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.danger)),
                          if (s.byCategory.isNotEmpty) const Divider(height: 24),
                          for (final c in s.byCategory)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(children: [
                                Expanded(child: Text(c.key, style: t.bodyMedium)),
                                Text(yer(c.value), style: t.bodyMedium),
                              ]),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final e in s.rows) _ExpenseTile(e),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseTile extends ConsumerWidget {
  const _ExpenseTile(this.e);

  final ExpenseRow e;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const IconBadge(Icons.payments_rounded, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.categoryName,
                      style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text(
                      '${e.spentAt}${e.description == null ? '' : ' • ${e.description}'}',
                      style: t.bodySmall),
                ],
              ),
            ),
            Text(yer(e.amount),
                style: t.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800, color: AppColors.danger)),
            IconButton(
              tooltip: 'إلغاء المصروف',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final ok = await confirm(context,
                    title: 'إلغاء المصروف',
                    message:
                        'سيُلغى هذا المصروف ويُسجَّل الإلغاء في سجل التدقيق. هل تريد المتابعة؟',
                    okLabel: 'إلغاء المصروف');
                if (!ok) return;
                try {
                  await ref.read(expenseRepositoryProvider).cancel(e.id);
                  ref.read(dataRevisionProvider.notifier).bump();
                } catch (err) {
                  if (context.mounted) {
                    showMessage(context, errorText(err), error: true);
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
