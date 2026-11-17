import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/helpers/date_range.dart';
import '../../../core/helpers/dates.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/ui_helpers.dart';
import '../../../shared/providers/core_providers.dart';
import '../../reports/presentation/report_view_page.dart';
import '../data/attendance_repository.dart';

/// تسجيل الحضور: دفعة ← تاريخ ← حالة كل طالب ← حفظ.
class AttendancePage extends ConsumerStatefulWidget {
  const AttendancePage({super.key});

  @override
  ConsumerState<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends ConsumerState<AttendancePage> {
  int? _batchId;
  String _date = Dates.iso(DateTime.now());

  Future<void> _openReport() async {
    final id = _batchId;
    if (id == null) return;
    final d = Dates.parse(_date);
    try {
      final data = await ref
          .read(reportRepositoryProvider)
          .attendance(id, DateRange.month(d));
      if (!mounted) return;
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ReportViewPage(data: data)));
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final batches = (ref.watch(batchesProvider).asData?.value ?? const [])
        .where((b) => b.status == 'open')
        .toList();
    final selected = batches.any((b) => b.id == _batchId) ? _batchId : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الحضور'),
        actions: [
          IconButton(
            tooltip: 'تقرير الحضور للشهر',
            onPressed: selected == null ? null : _openReport,
            icon: const Icon(Icons.bar_chart_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: selected,
                  isExpanded: true,
                  hint: const Text('اختر الدفعة'),
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.school_outlined)),
                  items: [
                    for (final b in batches)
                      DropdownMenuItem(value: b.id, child: Text(b.name)),
                  ],
                  onChanged: (v) => setState(() => _batchId = v),
                ),
                const SizedBox(height: 10),
                DateField(
                  value: _date,
                  lastDate: DateTime.now(),
                  onChanged: (v) {
                    if (v != null) setState(() => _date = v);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: selected == null
                ? EmptyState(
                    icon: Icons.fact_check_outlined,
                    title: batches.isEmpty
                        ? 'لا توجد دفعات مفتوحة'
                        : 'اختر دفعة لتسجيل الحضور',
                    message: batches.isEmpty
                        ? 'أنشئ دفعة وسجّل فيها طلابًا أولًا.'
                        : null,
                  )
                : _RosterLoader(batchId: selected, date: _date),
          ),
        ],
      ),
    );
  }
}

class _RosterLoader extends ConsumerWidget {
  const _RosterLoader({required this.batchId, required this.date});

  final int batchId;
  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roster = ref.watch(rosterProvider(RosterKey(batchId, date)));
    return roster.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(errorText(e))),
      data: (list) => list.isEmpty
          ? const EmptyState(
              icon: Icons.groups_outlined,
              title: 'لا يوجد طلاب نشطون في هذه الدفعة',
              message: 'سجّل طلابًا في الدفعة أولًا.',
            )
          : _RosterEditor(
              key: ValueKey('$batchId|$date'),
              batchId: batchId,
              date: date,
              roster: list,
            ),
    );
  }
}

Color _statusColor(AttendanceStatus s) => switch (s) {
      AttendanceStatus.present => AppColors.success,
      AttendanceStatus.absent => AppColors.danger,
      AttendanceStatus.late => AppColors.warning,
      AttendanceStatus.excused => const Color(0xFF5B6FB5),
      AttendanceStatus.leave => const Color(0xFF7B6A8F),
    };

class _RosterEditor extends ConsumerStatefulWidget {
  const _RosterEditor({
    super.key,
    required this.batchId,
    required this.date,
    required this.roster,
  });

  final int batchId;
  final String date;
  final List<RosterEntry> roster;

  @override
  ConsumerState<_RosterEditor> createState() => _RosterEditorState();
}

class _RosterEditorState extends ConsumerState<_RosterEditor> {
  late final Map<int, AttendanceStatus?> _status = {
    for (final r in widget.roster) r.enrollmentId: r.status,
  };
  late final Map<int, String> _notes = {
    for (final r in widget.roster)
      if (r.notes != null) r.enrollmentId: r.notes!,
  };
  bool _saving = false;

  int get _marked => _status.values.where((s) => s != null).length;

  void _setAll(AttendanceStatus s) =>
      setState(() => _status.updateAll((_, __) => s));

  Future<void> _editNote(RosterEntry r) async {
    final ctrl = TextEditingController(text: _notes[r.enrollmentId] ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('ملاحظة: ${r.name}'),
        content: TextField(controller: ctrl, autofocus: true, maxLines: 2),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('حفظ')),
        ],
      ),
    );
    final text = ctrl.text.trim();
    ctrl.dispose();
    if (ok == true) {
      setState(() {
        if (text.isEmpty) {
          _notes.remove(r.enrollmentId);
        } else {
          _notes[r.enrollmentId] = text;
        }
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final items = <AttendanceSaveItem>[
      for (final e in _status.entries)
        if (e.value != null)
          AttendanceSaveItem(e.key, e.value!, notes: _notes[e.key]),
    ];
    setState(() => _saving = true);
    try {
      final n = await ref
          .read(attendanceRepositoryProvider)
          .save(widget.batchId, widget.date, items);
      ref.read(dataRevisionProvider.notifier).bump();
      if (mounted) {
        showMessage(context,
            n == 0 ? 'لا توجد تغييرات للحفظ' : 'تم حفظ الحضور ($n)');
      }
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            children: [
              Expanded(
                  child: Text('سُجّل $_marked من ${widget.roster.length}',
                      style: t.bodySmall)),
              TextButton(
                  onPressed: () => _setAll(AttendanceStatus.present),
                  child: const Text('الكل حاضر')),
              TextButton(
                  onPressed: () => _setAll(AttendanceStatus.absent),
                  child: const Text('الكل غائب')),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            itemCount: widget.roster.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (c, i) {
              final r = widget.roster[i];
              final current = _status[r.enrollmentId];
              return AppCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text('${r.name}  •  ${r.studentNo}',
                            style: t.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      IconButton(
                        tooltip: 'ملاحظة',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                            _notes.containsKey(r.enrollmentId)
                                ? Icons.sticky_note_2_rounded
                                : Icons.sticky_note_2_outlined,
                            size: 20),
                        onPressed: () => _editNote(r),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final s in AttendanceStatus.values)
                          ChoiceChip(
                            label: Text(s.label),
                            selected: current == s,
                            selectedColor: _statusColor(s).withValues(alpha: 0.2),
                            labelStyle: TextStyle(
                                color: current == s ? _statusColor(s) : null,
                                fontWeight:
                                    current == s ? FontWeight.w700 : null),
                            onSelected: (_) =>
                                setState(() => _status[r.enrollmentId] = s),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: FilledButton(
              onPressed: (_saving || _marked == 0) ? null : _save,
              child: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ الحضور'),
            ),
          ),
        ),
      ],
    );
  }
}
