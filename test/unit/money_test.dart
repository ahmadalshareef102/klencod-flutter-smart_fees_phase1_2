import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fees/core/helpers/money.dart';

void main() {
  group('Money.parse', () {
    test('أرقام لاتينية مع فواصل', () => expect(Money.parse('50,000'), 50000));
    test('أرقام عربية هندية', () => expect(Money.parse('٥٠٬٠٠٠'), 50000));
    test('يرفض السالب', () => expect(Money.parse('-5'), isNull));
    test('يرفض الفارغ', () => expect(Money.parse('  '), isNull));
    test('يرفض الكسور', () => expect(Money.parse('10.5'), isNull));
    test('يرفض الحروف', () => expect(Money.parse('12ab'), isNull));
  });

  test('Money.format', () {
    expect(Money.format(50000), '50,000 ر.ي');
  });
}
