import 'package:flutter/material.dart';

import '../errors/app_exception.dart';

/// رسالة قصيرة أسفل الشاشة.
void showMessage(BuildContext context, String text, {bool error = false}) {
  final cs = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? cs.error : null,
    ));
}

/// نص خطأ عربي مناسب للعرض (يعرض رسالة AppException كما هي،
/// وأي خطأ آخر برسالة عامة بدل نص تقني).
String errorText(Object e) =>
    e is AppException ? e.message : 'حدث خطأ غير متوقع، حاول مرة أخرى';

/// تأكيد قبل العمليات الحساسة.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String okLabel = 'تأكيد',
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('إلغاء')),
        TextButton(
            onPressed: () => Navigator.pop(c, true), child: Text(okLabel)),
      ],
    ),
  );
  return r ?? false;
}

/// يعرض أرقامًا ثلاثية الفواصل.
String yer(int amount) {
  final neg = amount < 0;
  final s = amount.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${neg ? '-' : ''}$b ر.ي';
}
