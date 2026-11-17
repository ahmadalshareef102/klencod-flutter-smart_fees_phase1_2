import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/ui_helpers.dart';
import '../../../shared/providers/core_providers.dart';
import '../data/batch_repository.dart';

class BatchesPage extends ConsumerWidget {
  const BatchesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batches = ref.watch(batchesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('الدفعات')),
      floatingActionButton: batches.maybeWhen(
        data: (l) => l.isEmpty
            ? null
            : FloatingActionButton(
                onPressed: () => context.push('/batches/new'),
                child: const Icon(Icons.add)),
        orElse: () => null,
      ),
      body: batches.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(errorText(e))),
        data: (list) => list.isEmpty
            ? const _FirstRun()
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (c, i) => _BatchCard(list[i]),
              ),
      ),
    );
  }
}

class _BatchCard extends ConsumerWidget {
  const _BatchCard(this.b);

  final BatchSummary b;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final closed = b.status != 'open';
    return AppCard(
      onTap: () => context.push('/students?batch=${b.id}'),
      child: Row(
        children: [
          const IconBadge(Icons.school_rounded, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b.name,
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${b.type.label} • ${yer(b.fee)}',
                    style: t.bodySmall),
                const SizedBox(height: 2),
                Text('${b.studentCount} طالب${closed ? ' • مغلقة' : ''}',
                    style: t.bodySmall),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              final ok = await confirm(context,
                  title: v == 'closed' ? 'إغلاق الدفعة' : 'تفعيل الدفعة',
                  message: v == 'closed'
                      ? 'لن يمكن تسجيل طلاب جدد فيها، ولن تُضاف رسوم متكررة جديدة. السجلات تبقى كما هي.'
                      : 'ستعود الدفعة مفتوحة للتسجيل.');
              if (!ok) return;
              await ref.read(batchRepositoryProvider).setStatus(b.id, v);
              ref.read(dataRevisionProvider.notifier).bump();
            },
            itemBuilder: (_) => [
              if (!closed)
                const PopupMenuItem(value: 'closed', child: Text('إغلاق الدفعة'))
              else
                const PopupMenuItem(value: 'open', child: Text('إعادة فتح الدفعة')),
            ],
          ),
        ],
      ),
    );
  }
}

/// حالة البداية: خطوات واضحة بدل بيانات وهمية.
class _FirstRun extends StatelessWidget {
  const _FirstRun();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    const steps = [
      ('إنشاء دفعة', 'مجموعة أو صف مع رسومها'),
      ('إضافة طالب', 'سجّل الطلاب في تلك الدفعة'),
      ('متابعة الرسوم', 'اعرف من دفع ومن عليه متبقٍ'),
      ('تسجيل الدفعات', 'سند قبض لكل دفعة مستلمة'),
    ];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
            child: Container(
          width: 96,
          height: 96,
          decoration:
              BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
          child: Icon(Icons.school_rounded, size: 48, color: cs.primary),
        )),
        const SizedBox(height: 20),
        Text('جهّز معهدك',
            textAlign: TextAlign.center,
            style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('أربع خطوات وتبدأ بتحصيل الرسوم',
            textAlign: TextAlign.center, style: t.bodyMedium),
        const SizedBox(height: 24),
        for (var i = 0; i < steps.length; i++)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: i == 0 ? cs.primary : cs.primaryContainer,
              foregroundColor: i == 0 ? cs.onPrimary : cs.onPrimaryContainer,
              child: Text('${i + 1}'),
            ),
            title: Text(steps[i].$1,
                style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            subtitle: Text(steps[i].$2),
          ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => context.push('/batches/new'),
          icon: const Icon(Icons.add),
          label: const Text('إنشاء أول دفعة'),
        ),
      ],
    );
  }
}
