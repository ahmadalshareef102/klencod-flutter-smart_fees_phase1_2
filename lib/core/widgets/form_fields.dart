import 'package:flutter/material.dart';

import '../helpers/dates.dart';

/// عنوان حقل فوق الإدخال، مع نجمة للحقول الإلزامية.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6, right: 4),
      child: Text.rich(TextSpan(children: [
        if (required)
          TextSpan(
              text: '* ',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        TextSpan(
            text: text,
            style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      ])),
    );
  }
}

/// حقل تاريخ يفتح منتقي التاريخ ويحفظ yyyy-MM-dd.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint = 'اختر التاريخ',
    this.firstDate,
    this.lastDate,
    this.clearable = false,
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final String hint;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool clearable;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () async {
        final initial = value == null ? DateTime.now() : Dates.parse(value!);
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: firstDate ?? DateTime(1950),
          lastDate: lastDate ?? DateTime(2100),
        );
        if (picked != null) onChanged(Dates.iso(picked));
      },
      child: InputDecorator(
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.calendar_month_rounded),
          suffixIcon: clearable && value != null
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => onChanged(null))
              : null,
        ),
        child: Text(value ?? hint,
            style: value == null
                ? TextStyle(color: Theme.of(context).hintColor)
                : null),
      ),
    );
  }
}
