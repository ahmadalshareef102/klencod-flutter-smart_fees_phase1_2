import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/excel_service.dart';
import '../../../core/services/pdf_service.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/ui_helpers.dart';
import '../../../shared/providers/core_providers.dart';
import '../../receipts/presentation/pdf_preview_page.dart';
import '../domain/report_data.dart';

/// عرض تقرير: جدول + بحث + ملخص + طباعة PDF + تصدير Excel
/// (التصدير يشمل الصفوف المعروضة بعد البحث فقط).
class ReportViewPage extends ConsumerStatefulWidget {
  const ReportViewPage({super.key, required this.data});

  final ReportData data;

  @override
  ConsumerState<ReportViewPage> createState() => _ReportViewPageState();
}

class _ReportViewPageState extends ConsumerState<ReportViewPage> {
  String _q = '';

  Future<void> _pdf(ReportData shown) async {
    final inst = await ref.read(instituteRepositoryProvider).get();
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PdfPreviewPage(
        title: shown.title,
        build: () => PdfService.buildReport(shown, instituteName: inst?.name),
      ),
    ));
  }

  Future<void> _excel(ReportData shown) async {
    try {
      await ExcelService.share(shown);
    } catch (e) {
      if (mounted) showMessage(context, 'تعذر تصدير ملف Excel', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.data.filtered(_q);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.data.title, style: const TextStyle(fontSize: 18)),
        actions: [
          IconButton(
              tooltip: 'طباعة / PDF',
              onPressed: () => _pdf(shown),
              icon: const Icon(Icons.picture_as_pdf_outlined)),
          IconButton(
              tooltip: 'تصدير Excel',
              onPressed: shown.rows.isEmpty ? null : () => _excel(shown),
              icon: const Icon(Icons.table_chart_outlined)),
        ],
      ),
      body: Column(
        children: [
          if (widget.data.subtitle != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(widget.data.subtitle!, style: t.bodySmall)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(
                  hintText: 'بحث داخل التقرير',
                  prefixIcon: Icon(Icons.search_rounded)),
            ),
          ),
          Expanded(
            child: shown.rows.isEmpty
                ? const EmptyState(
                    icon: Icons.inbox_outlined, title: 'لا توجد بيانات في هذا التقرير')
                : SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowHeight: 44,
                        dataRowMinHeight: 40,
                        dataRowMaxHeight: 56,
                        columns: [
                          for (final c in shown.columns)
                            DataColumn(
                                label: Text(c,
                                    style: const TextStyle(fontWeight: FontWeight.w700))),
                        ],
                        rows: [
                          for (final r in shown.rows)
                            DataRow(cells: [
                              for (final c in r) DataCell(Text(ReportData.cellText(c))),
                            ]),
                        ],
                      ),
                    ),
                  ),
          ),
          if (shown.summary.isNotEmpty)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final s in shown.summary)
                      Chip(label: Text('${s.key}: ${s.value}')),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
