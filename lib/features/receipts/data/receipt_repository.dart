import 'package:sqflite/sqflite.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/helpers/arabic_words.dart';
import '../../institute/data/institute_repository.dart';

/// كل ما يلزم لطباعة سند قبض.
class ReceiptData {
  const ReceiptData({
    required this.receiptNo,
    required this.date,
    required this.studentName,
    required this.studentNo,
    required this.batchName,
    required this.amount,
    required this.amountWords,
    required this.method,
    required this.reason,
    required this.totalFees,
    required this.totalPaid,
    required this.remaining,
    required this.receiverName,
    required this.cancelled,
    required this.cancelReason,
    this.instituteName,
    this.institutePhone,
    this.instituteAddress,
  });

  final String receiptNo;
  final String date;
  final String studentName;
  final String studentNo;
  final String batchName;
  final int amount;
  final String amountWords;
  final String method;
  final String reason;
  final int totalFees;
  final int totalPaid;
  final int remaining;
  final String? receiverName;

  /// السند الملغى يبقى محفوظًا ويُطبع بحالة «ملغى».
  final bool cancelled;
  final String? cancelReason;
  final String? instituteName;
  final String? institutePhone;
  final String? instituteAddress;
}

class ReceiptRepository {
  ReceiptRepository(this._db, this._institute);

  final Database _db;
  final InstituteRepository _institute;

  static String methodLabel(String code) => switch (code) {
        'cash' => 'نقدًا',
        'transfer' => 'تحويل',
        _ => 'أخرى',
      };

  Future<ReceiptData> load(int paymentId) async {
    final rows = await _db.rawQuery('''
      SELECT p.id, p.amount, p.paid_at, p.method, p.receipt_no, p.receiver_name,
             p.notes, p.status, p.reversal_reason, e.id AS enrollment_id,
             e.final_fee, s.full_name, s.student_no,
             COALESCE(b.name, '—') AS batch_name
      FROM payments p
      JOIN enrollments e ON e.id = p.enrollment_id
      JOIN students s ON s.id = e.student_id
      LEFT JOIN batches b ON b.id = e.batch_id
      WHERE p.id = ?''', [paymentId]);
    if (rows.isEmpty) throw const AppException('السند غير موجود');
    final r = rows.first;

    final paidRow = await _db.rawQuery(
        "SELECT COALESCE(SUM(amount), 0) AS s FROM payments "
        "WHERE enrollment_id = ? AND status = 'active'",
        [r['enrollment_id']]);
    final paid = (paidRow.first['s'] as num).toInt();
    final fees = r['final_fee'] as int;
    final amount = r['amount'] as int;
    final inst = await _institute.get();
    final notes = r['notes'] as String?;

    return ReceiptData(
      receiptNo: r['receipt_no'] as String,
      date: r['paid_at'] as String,
      studentName: r['full_name'] as String,
      studentNo: r['student_no'] as String,
      batchName: r['batch_name'] as String,
      amount: amount,
      amountWords: ArabicWords.yemeniRial(amount),
      method: methodLabel(r['method'] as String),
      reason: (notes == null || notes.trim().isEmpty)
          ? 'رسوم دراسية - ${r['batch_name']}'
          : notes.trim(),
      totalFees: fees,
      totalPaid: paid,
      remaining: fees - paid,
      receiverName: r['receiver_name'] as String?,
      cancelled: r['status'] != 'active',
      cancelReason: r['reversal_reason'] as String?,
      instituteName: inst?.name,
      institutePhone: inst?.phone,
      instituteAddress: inst?.address,
    );
  }
}
