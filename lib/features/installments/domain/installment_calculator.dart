/// حالات القسط.
enum InstallmentStatus {
  notDue('not_due'),
  due('due'),
  partial('partial'),
  paid('paid'),
  late('late');

  const InstallmentStatus(this.code);
  final String code;
}

/// قسط له متبقٍ غير مسدد (مدخل لخوارزمية التخصيص).
class InstallmentDue {
  const InstallmentDue({
    required this.id,
    required this.remaining,
    required this.dueDate,
  });

  final int id;
  final int remaining;

  /// بصيغة yyyy-MM-dd.
  final String dueDate;
}

/// جزء من دفعة مخصص لقسط معيّن.
class AllocationShare {
  const AllocationShare(this.installmentId, this.amount);

  final int installmentId;
  final int amount;
}

/// حسابات الأقساط (دوال نقية بلا قاعدة بيانات، سهلة الاختبار).
class InstallmentCalculator {
  InstallmentCalculator._();

  /// تقسيم [total] على [count] قسطًا بأعداد صحيحة؛ الباقي يُوزَّع وحدة وحدة
  /// على الأقساط الأولى بحيث يساوي المجموع [total] تمامًا.
  static List<int> splitAmount(int total, int count) {
    if (total < 0) throw ArgumentError('المبلغ لا يمكن أن يكون سالبًا');
    if (count <= 0) throw ArgumentError('عدد الأقساط يجب أن يكون أكبر من صفر');
    final base = total ~/ count;
    final remainder = total % count;
    return List<int>.generate(count, (i) => base + (i < remainder ? 1 : 0));
  }

  /// تواريخ الاستحقاق: القسط الأول ثم كل [intervalDays] يومًا.
  static List<DateTime> dueDates(DateTime first, int count, int intervalDays) {
    return List<DateTime>.generate(
      count,
      (i) => DateTime.utc(first.year, first.month, first.day + i * intervalDays),
    );
  }

  static String formatDate(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-$m-$day';
  }

  /// حالة القسط. التأخر يعتمد على تاريخ الاستحقاق وليس على وجود رصيد فقط.
  /// [dueDate] و[today] بصيغة yyyy-MM-dd (المقارنة النصية صحيحة لهذه الصيغة).
  static InstallmentStatus statusFor({
    required int amount,
    required int paid,
    required String dueDate,
    required String today,
  }) {
    if (paid >= amount) return InstallmentStatus.paid;
    if (dueDate.compareTo(today) < 0) return InstallmentStatus.late;
    if (paid > 0) return InstallmentStatus.partial;
    if (dueDate == today) return InstallmentStatus.due;
    return InstallmentStatus.notDue;
  }

  /// توزيع تلقائي: الأقدم استحقاقًا أولًا. لا يتجاوز مجموع التخصيص [amount]
  /// ولا يتجاوز متبقي أي قسط. ما يتبقى من الدفعة يتعامل معه المستدعي.
  static List<AllocationShare> autoAllocate(
    int amount,
    List<InstallmentDue> dues,
  ) {
    final sorted = [...dues]..sort((a, b) {
        final c = a.dueDate.compareTo(b.dueDate);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    var left = amount;
    final result = <AllocationShare>[];
    for (final d in sorted) {
      if (left <= 0) break;
      if (d.remaining <= 0) continue;
      final take = left < d.remaining ? left : d.remaining;
      result.add(AllocationShare(d.id, take));
      left -= take;
    }
    return result;
  }
}
