import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../features/reports/domain/report_data.dart';

class ExcelService {
  ExcelService._();

  /// يبني ملف xlsx من التقرير (أرقامًا حقيقية لا نصوصًا) ويعيد بايتاته.
  static List<int> build(ReportData d) {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];
    sheet.appendRow([TextCellValue(d.title)]);
    if (d.subtitle != null) sheet.appendRow([TextCellValue(d.subtitle!)]);
    sheet.appendRow([for (final c in d.columns) TextCellValue(c)]);
    for (final r in d.rows) {
      sheet.appendRow([
        for (final c in r) c is int ? IntCellValue(c) : TextCellValue('$c'),
      ]);
    }
    if (d.summary.isNotEmpty) {
      sheet.appendRow([TextCellValue('')]);
      for (final s in d.summary) {
        sheet.appendRow([TextCellValue(s.key), TextCellValue(s.value)]);
      }
    }
    return excel.save() ?? <int>[];
  }

  /// يكتب الملف في مجلد مؤقت ويفتح نافذة المشاركة.
  static Future<void> share(ReportData d) async {
    final bytes = build(d);
    if (bytes.isEmpty) throw const FileSystemException('تعذر إنشاء الملف');
    final dir = await getTemporaryDirectory();
    final name = d.title.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    final f = File('${dir.path}/$name.xlsx');
    await f.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)]));
  }
}
