import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/helpers/date_range.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/ui_helpers.dart';
import '../../../shared/providers/core_providers.dart';
import '../data/report_repository.dart';
import '../domain/report_data.dart';
import 'report_view_page.dart';

/// مركز التقارير: اختر الفترة ثم التقرير.
class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

enum _Period { today, month, all }

class _ReportsPageState extends ConsumerState<ReportsPage> {
  _Period _period = _Period.month;

  DateRange get _range {
    final now = DateTime.now();
    return switch (_period) {
      _Period.today => DateRange.today(now),
      _Period.month => DateRange.month(now),
      _Period.all => DateRange.all,
    };
  }

  Future<void> _open(Future<ReportData> Function(ReportRepository r) build) async {
    try {
      final data = await build(ref.read(reportRepositoryProvider));
      if (!mounted) return;
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => ReportViewPage(data: data)));
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  Future<int?> _pickBatch() async {
    final batches = ref.read(batchesProvider).asData?.value ?? const [];
    if (batches.isEmpty) {
      showMessage(context, 'لا توجد دفعات بعد', error: true);
      return null;
    }
    return showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('اختر الدفعة'),
        children: [
          for (final b in batches)
            SimpleDialogOption(
                onPressed: () => Navigator.pop(c, b.id), child: Text(b.name)),
        ],
      ),
    );
  }

  Future<int?> _pickStudent() async {
    final list = await ref.read(studentRepositoryProvider).list();
    if (!mounted) return null;
    if (list.isEmpty) {
      showMessage(context, 'لا يوجد طلاب بعد', error: true);
      return null;
    }
    return showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('اختر الطالب'),
        children: [
          SizedBox(
            width: double.maxFinite,
            height: 360,
            child: ListView(children: [
              for (final s in list)
                ListTile(
                    title: Text(s.fullName),
                    onTap: () => Navigator.pop(c, s.id)),
            ]),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _range;
    final items = <(IconData, String, VoidCallback)>[
      (Icons.payments_rounded, 'تقرير التحصيل', () => _open((x) => x.collections(r))),
      (Icons.school_rounded, 'التحصيل حسب الدفعة', () => _open((x) => x.collectionsByBatch(r))),
      (Icons.money_off_rounded, 'الطلاب غير الدافعين', () => _open((x) => x.unpaidStudents())),
      (Icons.timelapse_rounded, 'الدفع الجزئي', () => _open((x) => x.partialStudents())),
      (Icons.warning_amber_rounded, 'المتأخرات', () => _open((x) => x.lateInstallments())),
      (Icons.event_rounded, 'الأقساط المستحقة (30 يومًا)', () => _open((x) => x.dueInstallments())),
      (Icons.percent_rounded, 'الخصومات', () => _open((x) => x.discounts())),
      (Icons.account_balance_wallet_rounded, 'المصروفات', () => _open((x) => x.expenses(r))),
      (Icons.swap_vert_rounded, 'صافي التدفق المالي', () => _open((x) => x.netCashFlow(r))),
      (Icons.person_rounded, 'كشف حساب طالب', () async {
        final id = await _pickStudent();
        if (id != null) await _open((x) => x.studentStatement(id));
      }),
      (Icons.menu_book_rounded, 'كشف حساب دفعة', () async {
        final id = await _pickBatch();
        if (id != null) await _open((x) => x.batchStatement(id));
      }),
      (Icons.apartment_rounded, 'كشف الحساب العام للمعهد', () => _open((x) => x.instituteStatement())),
      (Icons.groups_rounded, 'قائمة الطلاب', () => _open((x) => x.studentsList())),
      (Icons.fact_check_rounded, 'تقرير الحضور (الفترة)', () async {
        final id = await _pickBatch();
        if (id != null) await _open((x) => x.attendance(id, r));
      }),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('التقارير')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text('الفترة (للتحصيل والمصروفات والتدفق والحضور)',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final p in _Period.values)
              ChoiceChip(
                label: Text(switch (p) {
                  _Period.today => 'اليوم',
                  _Period.month => 'هذا الشهر',
                  _Period.all => 'الكل',
                }),
                selected: _period == p,
                onSelected: (_) => setState(() => _period = p),
              ),
          ]),
          const SizedBox(height: 12),
          for (final i in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                onTap: i.$3,
                child: Row(children: [
                  IconBadge(i.$1),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(i.$2,
                          style: Theme.of(context).textTheme.titleSmall)),
                  const Icon(Icons.chevron_left_rounded),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
