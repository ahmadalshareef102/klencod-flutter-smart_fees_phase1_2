import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fees/core/helpers/arabic_words.dart';

void main() {
  test('تفقيط المبالغ', () {
    expect(ArabicWords.convert(50000), 'خمسون ألف');
    expect(ArabicWords.convert(250000), 'مائتان وخمسون ألف');
    expect(ArabicWords.convert(200000), 'مائتا ألف');
    expect(ArabicWords.convert(1250000), 'مليون ومائتان وخمسون ألف');
    expect(ArabicWords.yemeniRial(50000), contains('ريال يمني فقط لا غير'));
  });
}
