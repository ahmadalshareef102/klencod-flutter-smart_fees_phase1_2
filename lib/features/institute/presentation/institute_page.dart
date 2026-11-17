import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/ui_helpers.dart';
import '../../../shared/providers/core_providers.dart';
import '../data/institute_repository.dart';

/// بيانات المعهد: تظهر في ترويسة السندات والتقارير.
class InstitutePage extends ConsumerStatefulWidget {
  const InstitutePage({super.key});

  @override
  ConsumerState<InstitutePage> createState() => _InstitutePageState();
}

class _InstitutePageState extends ConsumerState<InstitutePage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _manager = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _email = TextEditingController();
  final _year = TextEditingController();
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _manager, _phone, _address, _email, _year]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(instituteRepositoryProvider).save(InstituteInfo(
            name: _name.text,
            managerName: _manager.text,
            phone: _phone.text,
            address: _address.text,
            email: _email.text,
            academicYear: _year.text,
          ));
      ref.invalidate(instituteProvider);
      if (!mounted) return;
      showMessage(context, 'تم حفظ بيانات المعهد');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(instituteProvider);
    if (!_loaded && async.hasValue) {
      _loaded = true;
      final i = async.value;
      if (i != null) {
        _name.text = i.name;
        _manager.text = i.managerName ?? '';
        _phone.text = i.phone ?? '';
        _address.text = i.address ?? '';
        _email.text = i.email ?? '';
        _year.text = i.academicYear ?? '';
      }
    }
    if (async.isLoading && !_loaded) {
      return Scaffold(
          appBar: AppBar(title: const Text('إعدادات المعهد')),
          body: const Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات المعهد')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const FieldLabel('اسم المعهد', required: true),
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.apartment_rounded)),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'اسم المعهد مطلوب'
                        : null,
                  ),
                  const FieldLabel('اسم المدير'),
                  TextFormField(
                    controller: _manager,
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.person_outline)),
                  ),
                  const FieldLabel('رقم الهاتف'),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.phone_outlined)),
                  ),
                  const FieldLabel('العنوان'),
                  TextFormField(
                    controller: _address,
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.location_on_outlined)),
                  ),
                  const FieldLabel('البريد الإلكتروني (اختياري)'),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.email_outlined)),
                  ),
                  const FieldLabel('السنة الدراسية'),
                  TextFormField(
                    controller: _year,
                    decoration: const InputDecoration(
                        hintText: 'مثال: 2026/2027',
                        prefixIcon: Icon(Icons.calendar_month_outlined)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}
