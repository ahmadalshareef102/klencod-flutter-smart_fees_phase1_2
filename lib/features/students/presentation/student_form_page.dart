import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/helpers/dates.dart';
import '../../../core/helpers/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/ui_helpers.dart';
import '../../../shared/providers/core_providers.dart';
import '../../batches/data/batch_repository.dart';
import '../../payments/data/payment_repository.dart';
import '../data/student_repository.dart';

/// إضافة طالب جديد (مع تسجيله في دفعة اختياريًا) أو تعديل بياناته الشخصية.
class StudentFormPage extends ConsumerStatefulWidget {
  const StudentFormPage({super.key, this.studentId});

  final int? studentId;

  @override
  ConsumerState<StudentFormPage> createState() => _StudentFormPageState();
}

class _StudentFormPageState extends ConsumerState<StudentFormPage> {
  final _form = GlobalKey<FormState>();
  final _no = TextEditingController();
  final _name = TextEditingController();
  final _fee = TextEditingController();
  final _discount = TextEditingController();
  final _paid = TextEditingController();
  final _phone = TextEditingController();
  final _guardianPhone = TextEditingController();
  final _guardianName = TextEditingController();
  final _motherName = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();

  String _registeredAt = Dates.iso(DateTime.now());
  String? _birth;
  String? _gender;
  int? _batchId;
  PaymentMethod _method = PaymentMethod.cash;
  bool _saving = false;
  bool _loaded = false;

  bool get _editing => widget.studentId != null;

  /// الدفعة المختارة (تُبحث بالمعرّف حتى لا تنكسر القائمة عند إعادة التحميل).
  BatchSummary? get _selectedBatch {
    final list = ref.read(batchesProvider).asData?.value ?? const [];
    for (final b in list) {
      if (b.id == _batchId) return b;
    }
    return null;
  }

  @override
  void dispose() {
    for (final c in [
      _no, _name, _fee, _discount, _paid, _phone, _guardianPhone,
      _guardianName, _motherName, _address, _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// تعبئة النموذج مرة واحدة عند التعديل.
  void _fill(Map<String, Object?> s) {
    if (_loaded) return;
    _loaded = true;
    String v(String k) => (s[k] as String?) ?? '';
    _no.text = v('student_no');
    _name.text = v('full_name');
    _phone.text = v('phone');
    _guardianPhone.text = v('guardian_phone');
    _guardianName.text = v('guardian_name');
    _motherName.text = v('mother_name');
    _address.text = v('address');
    _notes.text = v('notes');
    _registeredAt = v('registered_at').isEmpty ? _registeredAt : v('registered_at');
    _birth = (s['birth_date'] as String?);
    _gender = s['gender'] as String?;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(studentRepositoryProvider);
      final input = StudentInput(
        studentNo: _no.text,
        fullName: _name.text,
        gender: _gender,
        phone: _phone.text,
        guardianPhone: _guardianPhone.text,
        guardianName: _guardianName.text,
        motherName: _motherName.text,
        birthDate: _birth,
        address: _address.text,
        notes: _notes.text,
        registeredAt: _registeredAt,
      );

      int? openId;
      if (_editing) {
        await repo.updateStudent(widget.studentId!, input);
      } else {
        final b = _selectedBatch;
        openId = await repo.createStudent(
          input,
          enroll: b == null
              ? null
              : EnrollInput(
                  batchId: b.id,
                  fee: Money.parse(_fee.text) ?? 0,
                  discount: Money.parse(_discount.text) ?? 0,
                  paidNow: Money.parse(_paid.text) ?? 0,
                  method: _method,
                ),
        );
      }
      ref.read(dataRevisionProvider.notifier).bump();
      if (!mounted) return;
      showMessage(context, _editing ? 'تم حفظ التعديلات' : 'تمت إضافة الطالب');
      Navigator.pop(context, openId);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      final d = ref.watch(studentDetailProvider(widget.studentId!));
      final data = d.asData?.value;
      if (data != null) _fill(data.student);
      if (d.isLoading && !_loaded) {
        return Scaffold(
            appBar: AppBar(title: const Text('تعديل الطالب')),
            body: const Center(child: CircularProgressIndicator()));
      }
    }

    final batches = ref.watch(batchesProvider).asData?.value
            .where((b) => b.status == 'open')
            .toList() ??
        const <BatchSummary>[];
    BatchSummary? batch;
    for (final b in batches) {
      if (b.id == _batchId) batch = b;
    }
    final recurring = batch?.type.isRecurring ?? false;

    String? required(String? v) =>
        (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null;
    final moneyFormatters = [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩,٬]')),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'تعديل الطالب' : 'طالب جديد'),
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
                  const FieldLabel('رقم القيد'),
                  TextFormField(
                    controller: _no,
                    decoration: const InputDecoration(
                        hintText: 'يُولَّد تلقائيًا إن تُرك فارغًا',
                        prefixIcon: Icon(Icons.pin_outlined)),
                  ),
                  const FieldLabel('الاسم', required: true),
                  TextFormField(
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                        hintText: 'الاسم الكامل',
                        prefixIcon: Icon(Icons.person_outline)),
                    validator: required,
                  ),
                  if (!_editing) ...[
                    const FieldLabel('اختر الدفعة (اختياري)'),
                    DropdownButtonFormField<int?>(
                      initialValue: batch?.id,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.school_outlined)),
                      hint: const Text('اختر الدفعة'),
                      items: [
                        const DropdownMenuItem<int?>(
                            value: null, child: Text('بدون دفعة الآن')),
                        for (final b in batches)
                          DropdownMenuItem<int?>(
                              value: b.id,
                              child: Text('${b.name} • ${b.type.label}')),
                      ],
                      onChanged: (id) => setState(() {
                        _batchId = id;
                        final picked = _selectedBatch;
                        _fee.text = picked == null ? '' : '${picked.fee}';
                      }),
                    ),
                    if (batches.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, right: 4),
                        child: Text(
                            'لا توجد دفعات مفتوحة. أنشئ دفعة أولًا لتسجيل الطالب فيها.',
                            style: Theme.of(context).textTheme.bodySmall),
                      ),
                    if (batch != null) ...[
                      FieldLabel(batch.type.feeLabel, required: true),
                      TextFormField(
                        controller: _fee,
                        keyboardType: TextInputType.number,
                        inputFormatters: moneyFormatters,
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
                      if (!recurring) ...[
                        const FieldLabel('الخصم (اختياري)'),
                        TextFormField(
                          controller: _discount,
                          keyboardType: TextInputType.number,
                          inputFormatters: moneyFormatters,
                          decoration: const InputDecoration(
                              hintText: '0',
                              prefixIcon: Icon(Icons.discount_outlined),
                              suffixText: 'ر.ي'),
                          validator: (v) {
                            if ((v ?? '').trim().isEmpty) return null;
                            final d = Money.parse(v!);
                            final f = Money.parse(_fee.text) ?? 0;
                            if (d == null) return 'مبلغ غير صالح';
                            if (d >= f) return 'الخصم يجب أن يكون أقل من الرسوم';
                            return null;
                          },
                        ),
                      ],
                      const FieldLabel('المدفوع الآن (اختياري)'),
                      TextFormField(
                        controller: _paid,
                        keyboardType: TextInputType.number,
                        inputFormatters: moneyFormatters,
                        decoration: const InputDecoration(
                            hintText: '0',
                            prefixIcon: Icon(Icons.price_check_rounded),
                            suffixText: 'ر.ي'),
                        validator: (v) {
                          if ((v ?? '').trim().isEmpty) return null;
                          final p = Money.parse(v!);
                          if (p == null) return 'مبلغ غير صالح';
                          final f = (Money.parse(_fee.text) ?? 0) -
                              (recurring ? 0 : (Money.parse(_discount.text) ?? 0));
                          if (p > f) return 'المدفوع أكبر من الرسوم';
                          return null;
                        },
                      ),
                      const FieldLabel('طريقة الدفع'),
                      SegmentedButton<PaymentMethod>(
                        segments: const [
                          ButtonSegment(
                              value: PaymentMethod.cash, label: Text('نقدًا')),
                          ButtonSegment(
                              value: PaymentMethod.transfer, label: Text('تحويل')),
                          ButtonSegment(
                              value: PaymentMethod.other, label: Text('أخرى')),
                        ],
                        selected: {_method},
                        onSelectionChanged: (s) =>
                            setState(() => _method = s.first),
                      ),
                    ],
                  ],
                  const FieldLabel('تاريخ الانضمام'),
                  DateField(
                    value: _registeredAt,
                    onChanged: (v) {
                      if (v != null) setState(() => _registeredAt = v);
                    },
                  ),
                ],
              ),
            ),
            const SectionTitle('تفاصيل إضافية'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const FieldLabel('هاتف الطالب (اختياري)'),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.phone_outlined)),
                  ),
                  const FieldLabel('هاتف ولي الأمر (اختياري)'),
                  TextFormField(
                    controller: _guardianPhone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.phone_in_talk_outlined)),
                  ),
                  const FieldLabel('الجنس (اختياري)'),
                  SegmentedButton<String>(
                    emptySelectionAllowed: true,
                    segments: const [
                      ButtonSegment(
                          value: 'male',
                          icon: Icon(Icons.male),
                          label: Text('ذكر')),
                      ButtonSegment(
                          value: 'female',
                          icon: Icon(Icons.female),
                          label: Text('أنثى')),
                    ],
                    selected: {if (_gender != null) _gender!},
                    onSelectionChanged: (s) =>
                        setState(() => _gender = s.isEmpty ? null : s.first),
                  ),
                  const FieldLabel('تاريخ الميلاد (اختياري)'),
                  DateField(
                    value: _birth,
                    hint: 'اختر التاريخ',
                    clearable: true,
                    lastDate: DateTime.now(),
                    onChanged: (v) => setState(() => _birth = v),
                  ),
                  const FieldLabel('اسم ولي الأمر (اختياري)'),
                  TextFormField(
                    controller: _guardianName,
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.person_outline)),
                  ),
                  const FieldLabel('اسم الأم (اختياري)'),
                  TextFormField(
                    controller: _motherName,
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.person_2_outlined)),
                  ),
                  const FieldLabel('العنوان (اختياري)'),
                  TextFormField(
                    controller: _address,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.location_on_outlined)),
                  ),
                  const FieldLabel('ملاحظة (اختياري)'),
                  TextFormField(
                    controller: _notes,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.sticky_note_2_outlined)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_editing ? 'حفظ التعديلات' : 'حفظ الطالب'),
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
