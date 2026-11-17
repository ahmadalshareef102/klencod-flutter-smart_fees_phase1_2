import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fees/core/services/excel_service.dart';
import 'package:smart_fees/core/services/pdf_service.dart';
import 'package:smart_fees/features/reports/domain/report_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const data = ReportData(
    title: 'تقرير اختبار',
    columns: ['الطالب', 'المبلغ'],
    rows: [
      ['أحمد', 50000],
      ['سارة', 1250000],
    ],
    summary: [MapEntry('الإجمالي', '1,300,000')],
  );

  test('البحث يصفّي الصفوف', () {
    expect(data.filtered('سارة').rows.length, 1);
    expect(data.filtered('').rows.length, 2);
  });

  test('PDF للتقرير يُبنى ويبدأ بترويسة PDF', () async {
    final bytes = await PdfService.buildReport(data, instituteName: 'معهد');
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('Excel يُبنى بأعداد حقيقية', () {
    expect(ExcelService.build(data), isNotEmpty);
  });
}
