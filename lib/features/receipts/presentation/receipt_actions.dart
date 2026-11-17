import 'package:flutter/material.dart';

import '../../../core/services/pdf_service.dart';
import '../data/receipt_repository.dart';
import 'pdf_preview_page.dart';

/// يفتح معاينة سند القبض (طباعة / مشاركة PDF).
void openReceipt(NavigatorState nav, ReceiptRepository repo, int paymentId,
    {String title = 'سند قبض'}) {
  nav.push(MaterialPageRoute(
    builder: (_) => PdfPreviewPage(
      title: title,
      build: () async => PdfService.buildReceipt(await repo.load(paymentId)),
    ),
  ));
}
