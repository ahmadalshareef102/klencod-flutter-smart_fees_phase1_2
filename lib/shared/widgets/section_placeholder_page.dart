import 'package:flutter/material.dart';

import '../../core/widgets/empty_state.dart';

/// صفحة مؤقتة لقسم لم تُنفَّذ مرحلته بعد (تُستبدل تدريجيًا بالشاشات الحقيقية).
class SectionPlaceholderPage extends StatelessWidget {
  const SectionPlaceholderPage({
    super.key,
    required this.title,
    required this.icon,
    required this.phase,
  });

  final String title;
  final IconData icon;
  final int phase;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: EmptyState(
        icon: icon,
        title: 'قسم $title',
        message: 'يُبنى هذا القسم في المرحلة $phase من خطة التنفيذ.',
      ),
    );
  }
}
