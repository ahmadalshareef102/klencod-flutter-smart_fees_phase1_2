import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/ui_helpers.dart';
import '../../../shared/providers/core_providers.dart';
import '../data/student_repository.dart';

/// جميع الطلاب، مع بحث فوري وتصفية بالدفعة.
class StudentsPage extends ConsumerStatefulWidget {
  const StudentsPage({super.key, this.initialBatchId});

  final int? initialBatchId;

  @override
  ConsumerState<StudentsPage> createState() => _StudentsPageState();
}

class _StudentsPageState extends ConsumerState<StudentsPage> {
  String _text = '';
  int? _batchId;

  @override
  void initState() {
    super.initState();
    _batchId = widget.initialBatchId;
  }

  @override
  Widget build(BuildContext context) {
    final q = StudentQuery(text: _text, batchId: _batchId);
    final students = ref.watch(studentsProvider(q));
    final batches = ref.watch(batchesProvider).asData?.value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('جميع الطلاب'),
        actions: [
          IconButton(
            tooltip: 'إضافة طالب',
            onPressed: () => context.push('/students/new'),
            icon: const Icon(Icons.add_circle_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _text = v),
              decoration: const InputDecoration(
                hintText: 'بحث بالاسم أو رقم القيد أو الهاتف…',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<int?>(
              initialValue: _batchId,
              isExpanded: true,
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.filter_list_rounded)),
              items: [
                const DropdownMenuItem<int?>(
                    value: null, child: Text('جميع الدفعات')),
                for (final b in batches)
                  DropdownMenuItem<int?>(value: b.id, child: Text(b.name)),
              ],
              onChanged: (v) => setState(() => _batchId = v),
            ),
          ),
          Expanded(
            child: students.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(errorText(e))),
              data: (list) {
                if (list.isEmpty) {
                  final filtered = _text.isNotEmpty || _batchId != null;
                  return EmptyState(
                    icon: Icons.groups_outlined,
                    title: filtered ? 'لا توجد نتائج' : 'لم يتم العثور على طلاب',
                    message: filtered
                        ? 'جرّب تغيير البحث أو الدفعة.'
                        : 'اضغط + لإضافة أول طالب.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: list.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (c, i) => i == 0
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 4, right: 4),
                          child: Text('إجمالي الطلاب: ${list.length}',
                              style: Theme.of(c).textTheme.bodySmall),
                        )
                      : _StudentTile(list[i - 1]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentTile extends StatelessWidget {
  const _StudentTile(this.s);

  final StudentRow s;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final owes = s.remaining > 0;
    return AppCard(
      onTap: () => context.push('/students/${s.id}'),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: cs.primaryContainer,
            foregroundColor: cs.onPrimaryContainer,
            child: Text(s.fullName.characters.first),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.fullName,
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text('رقم القيد ${s.studentNo}'
                    '${s.batches == null ? '' : ' • ${s.batches}'}',
                    style: t.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (s.fees > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: owes ? cs.primaryContainer : AppColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                owes ? 'متبقٍ ${yer(s.remaining)}' : 'مسدّد',
                style: t.labelMedium?.copyWith(
                    color: owes ? cs.onPrimaryContainer : AppColors.success,
                    fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}
