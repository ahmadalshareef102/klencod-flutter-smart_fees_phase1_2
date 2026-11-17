import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../helpers/money.dart';
import '../../features/receipts/data/receipt_repository.dart';
import '../../features/reports/domain/report_data.dart';

/// بناء ملفات PDF عربية (RTL) بخط Cairo المضمّن.
class PdfService {
  PdfService._();

  static pw.Font? _regular;
  static pw.Font? _bold;

  static Future<void> _loadFonts() async {
    _regular ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo-Regular.ttf'));
    _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo-Bold.ttf'));
  }

  static pw.ThemeData get _theme =>
      pw.ThemeData.withFont(base: _regular!, bold: _bold!);

  static const PdfColor _primary = PdfColor.fromInt(0xFF844E5C);
  static const PdfColor _soft = PdfColor.fromInt(0xFFFED9E1);
  static const PdfColor _line = PdfColor.fromInt(0xFFD9D0BE);

  // ------------------------------------------------------------- السند

  static Future<Uint8List> buildReceipt(ReceiptData d) async {
    await _loadFonts();
    final doc = pw.Document(theme: _theme, title: 'سند قبض ${d.receiptNo}');

    pw.Widget kv(String k, String v, {bool strong = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(children: [
            pw.SizedBox(
                width: 90,
                child: pw.Text(k, style: const pw.TextStyle(color: PdfColors.grey700))),
            pw.Expanded(
                child: pw.Text(v,
                    style: pw.TextStyle(
                        fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal))),
          ]),
        );

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5.landscape,
      margin: const pw.EdgeInsets.all(24),
      textDirection: pw.TextDirection.rtl,
      build: (ctx) => pw.Stack(children: [
        pw.Container(
          decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _primary, width: 1.5),
              borderRadius: pw.BorderRadius.circular(8)),
          padding: const pw.EdgeInsets.all(16),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Row(children: [
              pw.Expanded(
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(d.instituteName ?? 'سند قبض',
                      style: pw.TextStyle(
                          fontSize: 16, fontWeight: pw.FontWeight.bold, color: _primary)),
                  if (d.instituteAddress != null && d.instituteAddress!.isNotEmpty)
                    pw.Text(d.instituteAddress!, style: const pw.TextStyle(fontSize: 9)),
                  if (d.institutePhone != null && d.institutePhone!.isNotEmpty)
                    pw.Text('هاتف: ${d.institutePhone}', style: const pw.TextStyle(fontSize: 9)),
                ]),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: pw.BoxDecoration(
                    color: _soft, borderRadius: pw.BorderRadius.circular(6)),
                child: pw.Column(children: [
                  pw.Text('سند قبض',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                  pw.Text(d.receiptNo, style: const pw.TextStyle(fontSize: 10)),
                  pw.Text(d.date, style: const pw.TextStyle(fontSize: 10)),
                ]),
              ),
            ]),
            pw.Divider(color: _line),
            kv('استلمنا من', '${d.studentName}  (${d.studentNo})', strong: true),
            kv('الدفعة', d.batchName),
            kv('المبلغ', '${Money.group(d.amount)} ريال يمني', strong: true),
            kv('كتابةً', d.amountWords),
            kv('طريقة الدفع', d.method),
            kv('وذلك عن', d.reason),
            pw.Divider(color: _line),
            pw.Row(children: [
              pw.Expanded(child: kv('إجمالي الرسوم', Money.group(d.totalFees))),
              pw.Expanded(child: kv('إجمالي المدفوع', Money.group(d.totalPaid))),
              pw.Expanded(child: kv('المتبقي', Money.group(d.remaining), strong: true)),
            ]),
            pw.Spacer(),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('المستلم: ${d.receiverName ?? '................'}'),
              pw.Text('التوقيع: ................'),
            ]),
          ]),
        ),
        if (d.cancelled)
          pw.Center(
            child: pw.Transform.rotate(
              angle: 0.35,
              child: pw.Text('ملغى',
                  style: pw.TextStyle(
                      fontSize: 72,
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor(0.61, 0.22, 0.25, 0.35))),
            ),
          ),
      ]),
    ));
    return doc.save();
  }

  // ------------------------------------------------------------- التقرير

  static Future<Uint8List> buildReport(ReportData d, {String? instituteName}) async {
    await _loadFonts();
    final doc = pw.Document(theme: _theme, title: d.title);
    // RTL: نعكس ترتيب الأعمدة يدويًا ليظهر أول عمود على اليمين.
    List<T> rtl<T>(List<T> l) => l.reversed.toList();

    pw.Widget cell(String t, {bool head = false}) => pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          color: head ? _primary : null,
          child: pw.Text(t,
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: head ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: head ? PdfColors.white : PdfColors.black)),
        );

    pw.Widget row(List<String> cells, {bool head = false, bool alt = false}) =>
        pw.Container(
          color: alt ? const PdfColor.fromInt(0xFFF7F2E8) : null,
          child: pw.Row(children: [
            for (final c in rtl(cells)) pw.Expanded(child: cell(c, head: head)),
          ]),
        );

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      textDirection: pw.TextDirection.rtl,
      footer: (c) => pw.Align(
        alignment: pw.Alignment.center,
        child: pw.Text('صفحة ${c.pageNumber} من ${c.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ),
      build: (ctx) => [
        if (instituteName != null)
          pw.Text(instituteName, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.Text(d.title,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _primary)),
        if (d.subtitle != null)
          pw.Text(d.subtitle!, style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 10),
        row(d.columns, head: true),
        if (d.rows.isEmpty)
          pw.Padding(
              padding: const pw.EdgeInsets.all(16),
              child: pw.Center(child: pw.Text('لا توجد بيانات')))
        else
          for (var i = 0; i < d.rows.length; i++)
            row([for (final c in d.rows[i]) ReportData.cellText(c)], alt: i.isOdd),
        pw.SizedBox(height: 12),
        if (d.summary.isNotEmpty)
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
                color: _soft, borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              for (final s in d.summary)
                pw.Text('${s.key}: ${s.value}',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ]),
          ),
      ],
    ));
    return doc.save();
  }
}
