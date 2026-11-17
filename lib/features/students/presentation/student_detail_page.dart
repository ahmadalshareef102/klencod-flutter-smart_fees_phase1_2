import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/helpers/dates.dart';
import '../../../core/helpers/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/ui_helpers.dart';
import '../../../shared/providers/core_providers.dart';
import '../../../core/services/pdf_service.dart';
import '../../payments/data/payment_repository.dart';
import '../../receipts/presentation/pdf_preview_page.dart';
import '../../receipts/presentation/receipt_actions.dart';
import '../data/student_repository.dart';

class StudentDetailPage extends ConsumerWidget {
  const StudentDetailPage({super.key, required this.studentId});

  final int studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(studentDetailProvider(studentId));
    return async.when(
      loading: () => Scaffold(
          appBar: AppBar(),
          body: const Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          Scaffold(appBar: AppBar(), body: Center(child: Text(errorText(e)))),
      data: (d) {
        if (d == null) {
          return Scaffold(
              appBar: AppBar(),
              body: const Center(child: Text('الطالب غير موجود')));
        }
        return _Body(d, studentId);
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body(this.d, this.id);

  final StudentDetail d;
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final name = d.student['full_name'] as String;
    final archived = d.student['deleted_at'] != null;
    final payable = d.enrollments.where((e) => e.status == 'active').toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(name, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              final repo = ref.read(studentRepositoryProvider);
              if (v == 'edit') {
                context.push('/students/$id/edit');
              } else if (v == 'archive') {
                final ok = await confirm(context,
                    title: 'أرشفة الطالب',
                    message:
                        'سيختفي الطالب من القوائم، وتبقى كل سجلاته المالية محفوظة. يمكنك استعادته لاحقًا.',
                    okLabel: 'أرشفة');
                if (!ok) return;
                await repo.archive(id);
                ref.read(dataRevisionProvider.notifier).bump();
                if (context.mounted) context.pop();
              } else if (v == 'statement') {
                try {
                  final data = await ref
                      .read(reportRepositoryProvider)
                      .studentStatement(id);
                  final inst = await ref.read(instituteRepositoryProvider).get();
                  if (!context.mounted) return;
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PdfPreviewPage(
                      title: 'كشف حساب $name',
                      build: () =>
                          PdfService.buildReport(data, instituteName: inst?.name),
                    ),
                  ));
                } catch (e) {
                  if (context.mounted) {
                    showMessage(context, errorText(e), error: true);
                  }
                }
              } else if (v == 'restore') {
                await repo.restore(id);
                ref.read(dataRevisionProvider.notifier).bump();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('تعديل')),
              const PopupMenuItem(
                  value: 'statement', child: Text('كشف حساب الطالب (PDF)')),
              if (archived)
                const PopupMenuItem(value: 'restore', child: Text('استعادة'))
              else
                const PopupMenuItem(value: 'archive', child: Text('أرشفة')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          AppCard(
            child: Row(
              children: [
                const IconBadge(Icons.person_rounded, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: t.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      Text('رقم القيد ${d.student['student_no']}',
                          style: t.bodySmall),
                      if ((d.student['phone'] as String?) != null)
                        Text('${d.student['phone']}', style: t.bodySmall),
                      if (archived)
                        Text('مؤرشف',
                            style: t.labelMedium
                                ?.copyWith(color: AppColors.danger)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            _Money('الإجمالي', d.totalFees, null),
            const SizedBox(width: 8),
            _Money('المدفوع', d.totalPaid, AppColors.success),
            const SizedBox(width: 8),
            _Money('المتبقي', d.remaining < 0 ? 0 : d.remaining,
                d.remaining > 0 ? AppColors.danger : AppColors.success),
          ]),
          if (d.remaining < 0)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 4),
              child: Text('رصيد دائن للطالب: ${yer(-d.remaining)}',
                  style: t.bodySmall?.copyWith(color: AppColors.success)),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: payable.isEmpty
                ? null
                : () => showPaymentSheet(context, ref, payable),
            icon: const Icon(Icons.add_card_rounded),
            label: const Text('تسجيل دفعة'),
          ),
          if (payable.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 4),
              child: Text('الطالب غير مسجّل في أي دفعة. سجّله في دفعة لتسجيل مدفوعات.',
                  style: t.bodySmall),
            ),
          const SectionTitle('الأقساط'),
          if (d.enrollments.isEmpty)
            const AppCard(child: Text('لا توجد تسجيلات بعد'))
          else
            for (final e in d.enrollments) _EnrollmentCard(e),
          const SectionTitle('سجل المدفوعات'),
          if (d.payments.isEmpty)
            const AppCard(child: Text('لا توجد مدفوعات بعد'))
          else
            for (final p in d.payments) _PaymentTile(p),
        ],
      ),
    );
  }
}

class _Money extends StatelessWidget {
  const _Money(this.title, this.amount, this.color);

  final String title;
  final int amount;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Expanded(
      child: AppCard(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(children: [
          Text(title, style: t.bodySmall),
          const SizedBox(height: 4),
          FittedBox(
            child: Text(yer(amount),
                style: t.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color ?? Theme.of(context).colorScheme.primary)),
          ),
        ]),
      ),
    );
  }
}

String _statusLabel(String s) => switch (s) {
      'paid' => 'مدفوع',
      'partial' => 'جزئي',
      'late' => 'متأخر',
      'due' => 'مستحق اليوم',
      _ => 'لم يحن موعده',
    };

Color _statusColor(BuildContext c, String s) => switch (s) {
      'paid' => AppColors.success,
      'late' => AppColors.danger,
      'due' || 'partial' => AppColors.warning,
      _ => Theme.of(c).colorScheme.outline,
    };

class _EnrollmentCard extends StatelessWidget {
  const _EnrollmentCard(this.e);

  final EnrollmentView e;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${e.batchName} • ${e.batchType.label}',
                style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            Text('الرسوم ${yer(e.finalFee)} • المدفوع ${yer(e.paid)}',
                style: t.bodySmall),
            const Divider(height: 20),
            for (final i in e.installments)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  CircleAvatar(
                      radius: 12,
                      backgroundColor:
                          _statusColor(context, i.status).withValues(alpha: 0.15),
                      child: Text('${i.seq}',
                          style: t.labelSmall?.copyWith(
                              color: _statusColor(context, i.status)))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        '${yer(i.amount)} • يستحق ${i.dueDate}'
                        '${i.paid > 0 && i.paid < i.amount ? ' • مدفوع ${yer(i.paid)}' : ''}',
                        style: t.bodySmall),
                  ),
                  Text(_statusLabel(i.status),
                      style: t.labelMedium?.copyWith(
                          color: _statusColor(context, i.status),
                          fontWeight: FontWeight.w700)),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

class _PaymentTile extends ConsumerWidget {
  const _PaymentTile(this.p);

  final PaymentView p;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final method = switch (p.method) {
      'cash' => 'نقدًا',
      'transfer' => 'تحويل',
      _ => 'أخرى',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    yer(p.amount),
                    style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        decoration: p.isActive ? null : TextDecoration.lineThrough,
                        color: p.isActive ? AppColors.success : AppColors.danger),
                  ),
                  Text('${p.paidAt} • $method • سند ${p.receiptNo}',
                      style: t.bodySmall),
                  Text(p.batchName, style: t.bodySmall),
                  if (!p.isActive)
                    Text('ملغاة: ${p.reversalReason ?? ''}',
                        style: t.bodySmall?.copyWith(color: AppColors.danger)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'عرض السند',
              icon: const Icon(Icons.receipt_long_rounded),
              onPressed: () => openReceipt(Navigator.of(context),
                  ref.read(receiptRepositoryProvider), p.id,
                  title: 'سند ${p.receiptNo}'),
            ),
            if (p.isActive)
              IconButton(
                tooltip: 'عكس الدفعة',
                icon: const Icon(Icons.undo_rounded),
                onPressed: () => _reverse(context, ref),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _reverse(BuildContext context, WidgetRef ref) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('عكس الدفعة'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('سيُلغى السند ${p.receiptNo} وتُعاد المبالغ إلى الأقساط. تبقى الدفعة ظاهرة في السجل كملغاة.'),
          const SizedBox(height: 12),
          TextField(
            controller: reason,
            decoration: const InputDecoration(hintText: 'سبب العكس (مطلوب)'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('تراجع')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('عكس')),
        ],
      ),
    );
    final text = reason.text;
    reason.dispose();
    if (ok != true) return;
    try {
      await ref
          .read(paymentRepositoryProvider)
          .reversePayment(paymentId: p.id, reason: text);
      ref.read(dataRevisionProvider.notifier).bump();
      if (context.mounted) showMessage(context, 'تم عكس الدفعة');
    } catch (e) {
      if (context.mounted) showMessage(context, errorText(e), error: true);
    }
  }
}

/// نموذج تسجيل دفعة: مباشر في شاشة واحدة.
Future<void> showPaymentSheet(
    BuildContext context, WidgetRef ref, List<EnrollmentView> enrollments) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
      child: _PaymentSheet(enrollments: enrollments),
    ),
  );
}

class _PaymentSheet extends ConsumerStatefulWidget {
  const _PaymentSheet({required this.enrollments});

  final List<EnrollmentView> enrollments;

  @override
  ConsumerState<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<_PaymentSheet> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _receipt = TextEditingController();
  final _receiver = TextEditingController();
  final _notes = TextEditingController();
  late int _enrollmentId = widget.enrollments.first.id;
  String _date = Dates.iso(DateTime.now());
  PaymentMethod _method = PaymentMethod.cash;
  bool _saving = false;

  EnrollmentView get _enr =>
      widget.enrollments.firstWhere((e) => e.id == _enrollmentId);

  @override
  void initState() {
    super.initState();
    final rem = _enr.remaining;
    if (rem > 0) _amount.text = '$rem';
  }

  @override
  void dispose() {
    for (final c in [_amount, _receipt, _receiver, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final r = await ref.read(paymentRepositoryProvider).recordPayment(
            enrollmentId: _enrollmentId,
            amount: Money.parse(_amount.text) ?? 0,
            paidAt: _date,
            method: _method,
            receiptNo: _receipt.text,
            receiverName: _receiver.text.trim().isEmpty ? null : _receiver.text.trim(),
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      ref.read(dataRevisionProvider.notifier).bump();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final nav = Navigator.of(context);
      final receipts = ref.read(receiptRepositoryProvider);
      nav.pop();
      messenger.showSnackBar(SnackBar(
        content: Text('تم تسجيل الدفعة • سند ${r.receiptNo}'),
        action: SnackBarAction(
          label: 'عرض السند',
          onPressed: () => openReceipt(nav, receipts, r.paymentId,
              title: 'سند ${r.receiptNo}'),
        ),
      ));
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Form(
        key: _form,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text('تسجيل دفعة',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
            if (widget.enrollments.length > 1) ...[
              const FieldLabel('الدفعة'),
              DropdownButtonFormField<int>(
                initialValue: _enrollmentId,
                isExpanded: true,
                items: [
                  for (final e in widget.enrollments)
                    DropdownMenuItem(
                        value: e.id,
                        child: Text('${e.batchName} • متبقٍ ${yer(e.remaining)}')),
                ],
                onChanged: (v) => setState(() {
                  _enrollmentId = v!;
                  final rem = _enr.remaining;
                  _amount.text = rem > 0 ? '$rem' : '';
                }),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    '${_enr.batchName} • المتبقي ${yer(_enr.remaining < 0 ? 0 : _enr.remaining)}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            const FieldLabel('المبلغ', required: true),
            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩,٬]')),
              ],
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.payments_outlined), suffixText: 'ر.ي'),
              validator: (v) {
                final n = Money.parse(v ?? '');
                if (n == null || n <= 0) return 'أدخل مبلغًا أكبر من صفر';
                if (n > _enr.remaining) return 'المبلغ أكبر من المتبقي (${yer(_enr.remaining)})';
                return null;
              },
            ),
            const FieldLabel('تاريخ الدفع'),
            DateField(
                value: _date,
                onChanged: (v) {
                  if (v != null) setState(() => _date = v);
                }),
            const FieldLabel('طريقة الدفع'),
            SegmentedButton<PaymentMethod>(
              segments: const [
                ButtonSegment(value: PaymentMethod.cash, label: Text('نقدًا')),
                ButtonSegment(value: PaymentMethod.transfer, label: Text('تحويل')),
                ButtonSegment(value: PaymentMethod.other, label: Text('أخرى')),
              ],
              selected: {_method},
              onSelectionChanged: (s) => setState(() => _method = s.first),
            ),
            const FieldLabel('رقم السند (اختياري، يُولَّد تلقائيًا)'),
            TextFormField(
              controller: _receipt,
              decoration:
                  const InputDecoration(prefixIcon: Icon(Icons.receipt_long_outlined)),
            ),
            const FieldLabel('اسم المستلم (اختياري)'),
            TextFormField(
              controller: _receiver,
              decoration:
                  const InputDecoration(prefixIcon: Icon(Icons.person_outline)),
            ),
            const FieldLabel('ملاحظات (اختياري)'),
            TextFormField(
              controller: _notes,
              decoration:
                  const InputDecoration(prefixIcon: Icon(Icons.notes_rounded)),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('حفظ الدفعة'),
            ),
          ],
        ),
      ),
    );
  }
}
