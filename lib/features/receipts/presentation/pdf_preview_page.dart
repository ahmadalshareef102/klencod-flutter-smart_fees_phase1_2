import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// معاينة PDF مع الطباعة والمشاركة.
class PdfPreviewPage extends StatelessWidget {
  const PdfPreviewPage({super.key, required this.title, required this.build});

  final String title;
  final Future<Uint8List> Function() build;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: PdfPreview(
        build: (_) => build(),
        pdfFileName: '$title.pdf',
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
      ),
    );
  }
}
