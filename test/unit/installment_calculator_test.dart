import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fees/features/installments/domain/installment_calculator.dart';

void main() {
  group('splitAmount', () {
    test('10000 على قسطين', () {
      expect(InstallmentCalculator.splitAmount(10000, 2), [5000, 5000]);
    });

    test('الباقي يُوزَّع ويبقى المجموع مطابقًا', () {
      final parts = InstallmentCalculator.splitAmount(10000, 3);
      expect(parts, [3334, 3333, 3333]);
      expect(parts.reduce((a, b) => a + b), 10000);
    });

    test('يرفض عددًا غير صالح أو مبلغًا سالبًا', () {
      expect(() => InstallmentCalculator.splitAmount(100, 0), throwsArgumentError);
      expect(() => InstallmentCalculator.splitAmount(-1, 2), throwsArgumentError);
    });
  });

  test('dueDates بفاصل 30 يومًا', () {
    final d = InstallmentCalculator.dueDates(DateTime(2026, 1, 15), 3, 30);
    expect(d.map(InstallmentCalculator.formatDate).toList(),
        ['2026-01-15', '2026-02-14', '2026-03-16']);
  });

  group('statusFor', () {
    InstallmentStatus st(int paid, String due) => InstallmentCalculator.statusFor(
        amount: 5000, paid: paid, dueDate: due, today: '2026-11-16');

    test('مدفوع بالكامل', () => expect(st(5000, '2026-01-01'), InstallmentStatus.paid));
    test('متأخر بحسب تاريخ الاستحقاق', () => expect(st(0, '2026-11-15'), InstallmentStatus.late));
    test('متأخر مع دفع جزئي', () => expect(st(1000, '2026-11-15'), InstallmentStatus.late));
    test('مستحق اليوم', () => expect(st(0, '2026-11-16'), InstallmentStatus.due));
    test('جزئي لم يحن موعده', () => expect(st(1000, '2026-12-01'), InstallmentStatus.partial));
    test('لم يحن موعده', () => expect(st(0, '2026-12-01'), InstallmentStatus.notDue));
  });

  group('autoAllocate', () {
    const dues = [
      InstallmentDue(id: 2, remaining: 5000, dueDate: '2026-12-01'),
      InstallmentDue(id: 1, remaining: 5000, dueDate: '2026-11-01'),
    ];

    test('الأقدم استحقاقًا أولًا', () {
      final r = InstallmentCalculator.autoAllocate(3000, dues);
      expect(r.length, 1);
      expect(r.first.installmentId, 1);
      expect(r.first.amount, 3000);
    });

    test('دفعة تغطي أكثر من قسط', () {
      final r = InstallmentCalculator.autoAllocate(7500, dues);
      expect(r.map((e) => (e.installmentId, e.amount)).toList(),
          [(1, 5000), (2, 2500)]);
    });

    test('لا يتجاوز مجموع التخصيص قيمة الدفعة ولا المتبقي', () {
      final r = InstallmentCalculator.autoAllocate(99999, dues);
      expect(r.fold<int>(0, (s, a) => s + a.amount), 10000);
    });
  });
}
