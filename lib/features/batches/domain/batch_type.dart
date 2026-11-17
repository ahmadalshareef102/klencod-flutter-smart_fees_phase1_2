/// أنواع الدفعات (طريقة احتساب الرسوم).
enum BatchType {
  monthlyRecurring(
    'monthly_recurring',
    'شهري (متكرر)',
    'رسوم تُحتسب كل شهر، ويزيد الإجمالي مع كل شهر جديد',
    periodMonths: 1,
  ),
  monthlyTotal(
    'monthly_total',
    'شهري (إجمالي)',
    'رسوم واحدة للدفعة كاملة، ويقسَّم الإجمالي على أشهرها',
  ),
  fixedCourse(
    'fixed_course',
    'دورة (مدة ثابتة)',
    'أشهر ثابتة مثل دورات 3/4/6 أشهر، يقسَّم إجماليها على الأشهر',
  ),
  yearly(
    'yearly',
    'سنوي',
    'رسوم تُحتسب مرة كل سنة',
    periodMonths: 12,
  ),
  quarterly(
    'quarterly',
    'ربع سنوي',
    'رسوم تُحتسب كل 3 أشهر',
    periodMonths: 3,
  ),
  custom(
    'custom',
    'مخصص',
    'رسوم واحدة تُستحق في تاريخ بداية الدفعة',
  ),
  installments(
    'installments',
    'أقساط',
    'إجمالي واحد مقسَّم إلى أقساط مجدولة',
  );

  const BatchType(this.code, this.label, this.description, {this.periodMonths});

  final String code;
  final String label;
  final String description;

  /// غير null = رسوم متكررة تتراكم كل [periodMonths] شهرًا.
  final int? periodMonths;

  bool get isRecurring => periodMonths != null;

  /// هل يلزم تاريخ نهاية للدفعة؟
  bool get needsEndDate => this == monthlyTotal || this == fixedCourse;

  String get feeLabel {
    switch (this) {
      case monthlyRecurring:
        return 'مبلغ الرسوم لكل شهر';
      case quarterly:
        return 'مبلغ الرسوم لكل 3 أشهر';
      case yearly:
        return 'مبلغ الرسوم السنوي';
      default:
        return 'إجمالي الرسوم';
    }
  }

  static BatchType fromCode(String code) =>
      BatchType.values.firstWhere((t) => t.code == code,
          orElse: () => BatchType.custom);
}
