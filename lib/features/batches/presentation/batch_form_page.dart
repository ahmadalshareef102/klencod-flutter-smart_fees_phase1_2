import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/helpers/dates.dart';
import '../../../core/helpers/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/ui_helpers.dart';
import '../../../shared/providers/core_providers.dart';
import '../data/batch_repository.dart' show BatchInput;
import '../domain/batch_type.dart';

class BatchFormPage extends ConsumerStatefulWidget {
  const BatchFormPage({super.key});

  @override
  ConsumerState<BatchFormPage> createState() => _BatchFormPageState();
}

class _BatchFormPageState extends ConsumerState<BatchFormPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _fee = TextEditingController();
  final _days = TextEditingController();
  final _subject = TextEditingController();
  final _count = TextEditingController(text: '3');
  final _interval = TextEditingController(text: '30');

  BatchType _type = BatchType.monthlyRecurring;
  String? _start = Dates.iso(DateTime.now());
  String? _end;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _fee, _days, _subject, _count, _interval]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickType() async {
    final picked = await showModalBottomSheet<BatchType>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('اختر نوع الدفعة',
                  textAlign: TextAlign.center,
                  style: Theme.of(c).textTheme.titleLarge),
            ),
            for (final t in BatchType.values)
              ListTile(
                selected: t == _type,
                leading: const IconBadge(Icons.layers_rounded, size: 42),
                title: Text(t.label),
                subtitle: Text(t.description),
                onTap: () => Navigator.pop(c, t),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _type = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(batchRepositoryProvider).create(BatchInput(
            name: _name.text,
            type: _type,
            fee: Money.parse(_fee.text) ?? 0,
            startDate: _start ?? '',
            endDate: _end,
            subject: _subject.text,
            daysCount: int.tryParse(_days.text) ?? 0,
            installmentsCount: int.tryParse(_count.text) ?? 1,
            intervalDays: int.tryParse(_interval.text) ?? 30,
          ));
      ref.read(dataRevisionProvider.notifier).bump();
      if (!mounted) return;
      showMessage(context, 'تم إنشاء الدفعة');
      Navigator.pop(context);
    } catch (e) {
      // النموذج يبقى كما هو عند الفشل.
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? required(String? v) =>
        (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('دفعة جديدة'),
        actions: [
          IconButton(
            tooltip: 'حفظ',
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_circle_rounded),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const FieldLabel('اسم الدفعة', required: true),
                  TextFormField(
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                        hintText: 'أدخل اسم الدفعة',
                        prefixIcon: Icon(Icons.badge_outlined)),
                    validator: required,
                  ),
                  const FieldLabel('نوع الدفعة'),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _pickType,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.layers_rounded),
                          suffixIcon: Icon(Icons.arrow_drop_down)),
                      child: Text(_type.label),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 4),
                    child: Text(
                      'ملاحظة: لا يُنصح بتغيير نوع الدفعة لاحقًا، فاختره بعناية. ${_type.description}.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                  FieldLabel(_type.feeLabel, required: true),
                  TextFormField(
                    controller: _fee,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩,٬]')),
                    ],
                    decoration: const InputDecoration(
                        hintText: 'أدخل المبلغ',
                        prefixIcon: Icon(Icons.payments_outlined),
                        suffixText: 'ر.ي'),
                    validator: (v) {
                      final n = Money.parse(v ?? '');
                      if (n == null || n <= 0) return 'أدخل مبلغًا صحيحًا أكبر من صفر';
                      return null;
                    },
                  ),
                  if (_type == BatchType.installments) ...[
                    const FieldLabel('عدد الأقساط', required: true),
                    TextFormField(
                      controller: _count,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.format_list_numbered)),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        return (n == null || n < 2) ? 'أدخل 2 أو أكثر' : null;
                      },
                    ),
                    const FieldLabel('الفاصل بين الأقساط (أيام)', required: true),
                    TextFormField(
                      controller: _interval,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.date_range)),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        return (n == null || n < 1) ? 'أدخل يومًا أو أكثر' : null;
                      },
                    ),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const FieldLabel('تاريخ البدء', required: true),
                            DateField(
                                value: _start,
                                hint: 'اختر تاريخ البدء',
                                onChanged: (v) => setState(() => _start = v)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FieldLabel('تاريخ الانتهاء',
                                required: _type.needsEndDate),
                            DateField(
                                value: _end,
                                hint: 'اختر تاريخ الانتهاء',
                                clearable: !_type.needsEndDate,
                                onChanged: (v) => setState(() => _end = v)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const FieldLabel('الأيام (اختياري)'),
                  TextFormField(
                    controller: _days,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        hintText: '0', prefixIcon: Icon(Icons.view_headline)),
                  ),
                  const FieldLabel('المادة (اختياري)'),
                  TextFormField(
                    controller: _subject,
                    decoration: const InputDecoration(
                        hintText: 'أدخل اسم المادة',
                        prefixIcon: Icon(Icons.subject)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('حفظ الدفعة'),
            ),
            TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
          ],
        ),
      ),
    );
  }
}
