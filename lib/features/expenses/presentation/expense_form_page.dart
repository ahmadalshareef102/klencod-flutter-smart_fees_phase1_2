import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/helpers/dates.dart';
import '../../../core/helpers/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/ui_helpers.dart';
import '../../../shared/providers/core_providers.dart';
import '../../payments/data/payment_repository.dart';
import '../data/expense_repository.dart';

class ExpenseFormPage extends ConsumerStatefulWidget {
  const ExpenseFormPage({super.key});

  @override
  ConsumerState<ExpenseFormPage> createState() => _ExpenseFormPageState();
}

class _ExpenseFormPageState extends ConsumerState<ExpenseFormPage> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _desc = TextEditingController();
  final _notes = TextEditingController();
  int? _categoryId;
  String _date = Dates.iso(DateTime.now());
  PaymentMethod _method = PaymentMethod.cash;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _desc.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _newCategory() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تصنيف جديد'),
        content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'اسم التصنيف')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('إضافة')),
        ],
      ),
    );
    final name = ctrl.text;
    ctrl.dispose();
    if (ok != true) return;
    try {
      final id = await ref.read(expenseRepositoryProvider).addCategory(name);
      ref.invalidate(expenseCategoriesProvider);
      setState(() => _categoryId = id);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(expenseRepositoryProvider).add(ExpenseInput(
            categoryId: _categoryId!,
            amount: Money.parse(_amount.text) ?? 0,
            spentAt: _date,
            description: _desc.text,
            method: _method,
            notes: _notes.text,
          ));
      ref.read(dataRevisionProvider.notifier).bump();
      if (!mounted) return;
      showMessage(context, 'تم تسجيل المصروف');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(expenseCategoriesProvider).asData?.value ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('مصروف جديد'),
        actions: [
          IconButton(
            tooltip: 'حفظ',
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check_circle_rounded),
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
                  const FieldLabel('نوع المصروف', required: true),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: cats.any((c) => c.id == _categoryId)
                            ? _categoryId
                            : null,
                        isExpanded: true,
                        hint: const Text('اختر النوع'),
                        items: [
                          for (final c in cats)
                            DropdownMenuItem(value: c.id, child: Text(c.name)),
                        ],
                        onChanged: (v) => setState(() => _categoryId = v),
                        validator: (v) => v == null ? 'اختر نوع المصروف' : null,
                      ),
                    ),
                    IconButton(
                      tooltip: 'تصنيف جديد',
                      onPressed: _newCategory,
                      icon: const Icon(Icons.add_circle_outline_rounded),
                    ),
                  ]),
                  const FieldLabel('المبلغ', required: true),
                  TextFormField(
                    controller: _amount,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩,٬]')),
                    ],
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.payments_outlined),
                        suffixText: 'ر.ي'),
                    validator: (v) {
                      final n = Money.parse(v ?? '');
                      return (n == null || n <= 0)
                          ? 'أدخل مبلغًا أكبر من صفر'
                          : null;
                    },
                  ),
                  const FieldLabel('التاريخ'),
                  DateField(
                    value: _date,
                    lastDate: DateTime.now(),
                    onChanged: (v) {
                      if (v != null) setState(() => _date = v);
                    },
                  ),
                  const FieldLabel('طريقة الدفع'),
                  SegmentedButton<PaymentMethod>(
                    segments: const [
                      ButtonSegment(value: PaymentMethod.cash, label: Text('نقدًا')),
                      ButtonSegment(
                          value: PaymentMethod.transfer, label: Text('تحويل')),
                      ButtonSegment(value: PaymentMethod.other, label: Text('أخرى')),
                    ],
                    selected: {_method},
                    onSelectionChanged: (s) => setState(() => _method = s.first),
                  ),
                  const FieldLabel('الوصف (اختياري)'),
                  TextFormField(
                    controller: _desc,
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.subject_rounded)),
                  ),
                  const FieldLabel('ملاحظات (اختياري)'),
                  TextFormField(
                    controller: _notes,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.notes_rounded)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('حفظ المصروف'),
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
