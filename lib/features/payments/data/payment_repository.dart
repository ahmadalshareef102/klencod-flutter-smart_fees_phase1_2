import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/audit_log.dart';
import '../../../core/errors/app_exception.dart';
import '../../installments/domain/installment_calculator.dart';

enum PaymentMethod {
  cash('cash'),
  transfer('transfer'),
  other('other');

  const PaymentMethod(this.code);
  final String code;
}

/// نتيجة تسجيل دفعة.
class PaymentResult {
  const PaymentResult({
    required this.paymentId,
    required this.receiptNo,
    required this.allocations,
    required this.onAccountAmount,
  });

  final int paymentId;
  final String receiptNo;

  /// التخصيصات على الأقساط.
  final List<AllocationShare> allocations;

  /// الجزء المسجّل على الحساب دون قسط محدد.
  final int onAccountAmount;
}

/// رصيد التسجيل. المتبقي سالب = رصيد دائن للطالب.
class EnrollmentBalance {
  const EnrollmentBalance({required this.finalFee, required this.paid});

  final int finalFee;
  final int paid;

  int get remaining => finalFee - paid;
  int get credit => remaining < 0 ? -remaining : 0;
}

/// العمليات المالية للدفعات. كل عملية كتابة داخل معاملة SQLite واحدة،
/// وأي فشل يتراجع عن كل شيء (الدفعة والتخصيص والأقساط والسند والتدقيق).
class PaymentRepository {
  PaymentRepository(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Database _db;
  final DateTime Function() _clock;

  String get _nowIso => _clock().toUtc().toIso8601String();
  String get _today => InstallmentCalculator.formatDate(_clock());

  /// الرصيد محسوب من سجل الدفعات الفعّالة، لا من رقم مخزَّن قابل للتعديل.
  Future<EnrollmentBalance> getBalance(int enrollmentId) async {
    final enr = await _db.query(
      'enrollments',
      columns: ['final_fee'],
      where: 'id = ?',
      whereArgs: [enrollmentId],
      limit: 1,
    );
    if (enr.isEmpty) throw const AppException('التسجيل غير موجود');
    return EnrollmentBalance(
      finalFee: enr.first['final_fee'] as int,
      paid: await _activePaid(_db, enrollmentId),
    );
  }

  Future<int> _activePaid(DatabaseExecutor ex, int enrollmentId) async {
    final r = await ex.rawQuery(
      "SELECT COALESCE(SUM(amount), 0) AS s FROM payments "
      "WHERE enrollment_id = ? AND status = 'active'",
      [enrollmentId],
    );
    return (r.first['s'] as num).toInt();
  }

  /// تسجيل دفعة.
  /// - [manualAllocations]: معرّف القسط -> المبلغ. إن كانت null يُوزَّع
  ///   المبلغ تلقائيًا على الأقدم استحقاقًا أولًا.
  /// - ما لا يغطي قسطًا يُسجَّل "على الحساب".
  /// - الدفع الزائد عن المتبقي مرفوض إلا مع [allowOverpayment] (رصيد دائن).
  Future<PaymentResult> recordPayment({
    required int enrollmentId,
    required int amount,
    required String paidAt,
    required PaymentMethod method,
    String? receiptNo,
    String? receiverName,
    String? notes,
    Map<int, int>? manualAllocations,
    bool allowOverpayment = false,
    int? createdBy,
  }) async {
    if (amount <= 0) {
      throw const AppException('المبلغ يجب أن يكون أكبر من صفر');
    }
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(paidAt)) {
      throw const AppException('تاريخ الدفع غير صالح');
    }

    return _db.transaction((txn) => recordPaymentIn(
          txn,
          enrollmentId: enrollmentId,
          amount: amount,
          paidAt: paidAt,
          method: method,
          receiptNo: receiptNo,
          receiverName: receiverName,
          notes: notes,
          manualAllocations: manualAllocations,
          allowOverpayment: allowOverpayment,
          createdBy: createdBy,
        ));
  }

  /// نفس [recordPayment] لكن داخل معاملة قائمة (مثلًا عند تسجيل طالب مع دفعة أولى).
  Future<PaymentResult> recordPaymentIn(
    Transaction txn, {
    required int enrollmentId,
    required int amount,
    required String paidAt,
    required PaymentMethod method,
    String? receiptNo,
    String? receiverName,
    String? notes,
    Map<int, int>? manualAllocations,
    bool allowOverpayment = false,
    int? createdBy,
  }) async {
    if (amount <= 0) {
      throw const AppException('المبلغ يجب أن يكون أكبر من صفر');
    }
    // 1) التحقق من التسجيل والرصيد.
    final enr = await txn.query(
      'enrollments',
      columns: ['final_fee', 'status'],
      where: 'id = ?',
      whereArgs: [enrollmentId],
      limit: 1,
    );
    if (enr.isEmpty) throw const AppException('التسجيل غير موجود');
    if (enr.first['status'] == 'cancelled') {
      throw const AppException('لا يمكن تسجيل دفعة على تسجيل ملغى');
    }
    final finalFee = enr.first['final_fee'] as int;
    final paidSoFar = await _activePaid(txn, enrollmentId);
    if (!allowOverpayment && amount > finalFee - paidSoFar) {
      throw const AppException('المبلغ أكبر من المتبقي على الطالب');
    }

    // 2) خطة التخصيص على الأقساط.
    final rows = await txn.query(
      'installments',
      where: 'enrollment_id = ? AND paid_amount < amount',
      whereArgs: [enrollmentId],
      orderBy: 'due_date, seq',
    );
    final byId = {for (final r in rows) r['id'] as int: r};
    final dues = rows
        .map((r) => InstallmentDue(
              id: r['id'] as int,
              remaining: (r['amount'] as int) - (r['paid_amount'] as int),
              dueDate: r['due_date'] as String,
            ))
        .toList();
    final shares = manualAllocations == null
        ? InstallmentCalculator.autoAllocate(amount, dues)
        : _validateManual(amount, dues, manualAllocations);
    final allocated = shares.fold<int>(0, (s, a) => s + a.amount);
    final onAccount = amount - allocated;
    if (onAccount < 0) {
      throw const AppException('مجموع التخصيص يتجاوز قيمة الدفعة');
    }

    // 3) رقم السند الفريد.
    final resolvedReceipt = await _resolveReceiptNo(txn, receiptNo);

    // 4) الدفعة.
    final paymentId = await txn.insert('payments', {
      'uuid': _uuid(),
      'enrollment_id': enrollmentId,
      'amount': amount,
      'paid_at': paidAt,
      'method': method.code,
      'receipt_no': resolvedReceipt,
      'receiver_name': receiverName,
      'notes': notes,
      'created_by': createdBy,
    });

    // 5) التخصيصات وتحديث الأقساط.
    final now = _nowIso;
    for (final s in shares) {
      await txn.insert('payment_allocations', {
        'payment_id': paymentId,
        'installment_id': s.installmentId,
        'amount': s.amount,
      });
      final row = byId[s.installmentId]!;
      final newPaid = (row['paid_amount'] as int) + s.amount;
      await txn.update(
        'installments',
        {
          'paid_amount': newPaid,
          'status': InstallmentCalculator.statusFor(
            amount: row['amount'] as int,
            paid: newPaid,
            dueDate: row['due_date'] as String,
            today: _today,
          ).code,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [s.installmentId],
      );
    }
    if (onAccount > 0) {
      await txn.insert('payment_allocations', {
        'payment_id': paymentId,
        'installment_id': null,
        'amount': onAccount,
      });
    }

    // 6) السند.
    await txn.insert('receipts', {
      'payment_id': paymentId,
      'receipt_no': resolvedReceipt,
      'status': 'active',
    });

    // 7) التدقيق.
    await writeAudit(
      txn,
      entity: 'payment',
      entityId: paymentId,
      action: 'create',
      details: {
        'enrollment_id': enrollmentId,
        'amount': amount,
        'receipt_no': resolvedReceipt,
        'on_account': onAccount,
      },
      actorId: createdBy,
    );

    return PaymentResult(
      paymentId: paymentId,
      receiptNo: resolvedReceipt,
      allocations: shares,
      onAccountAmount: onAccount,
    );
  }

  /// عكس دفعة (لا حذف): يُسترجع التخصيص وتُلغى الدفعة والسند مع حفظ السبب.
  Future<void> reversePayment({
    required int paymentId,
    required String reason,
    int? actorId,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      throw const AppException('سبب العكس مطلوب');
    }

    await _db.transaction((txn) async {
      final p = await txn.query(
        'payments',
        where: 'id = ?',
        whereArgs: [paymentId],
        limit: 1,
      );
      if (p.isEmpty) throw const AppException('الدفعة غير موجودة');
      if (p.first['status'] != 'active') {
        throw const AppException('هذه الدفعة معكوسة مسبقًا');
      }
      final now = _nowIso;

      final allocs = await txn.query(
        'payment_allocations',
        where: 'payment_id = ? AND reversed_at IS NULL',
        whereArgs: [paymentId],
      );
      for (final a in allocs) {
        final instId = a['installment_id'] as int?;
        if (instId != null) {
          final inst = (await txn.query(
            'installments',
            where: 'id = ?',
            whereArgs: [instId],
            limit: 1,
          ))
              .first;
          final newPaid = (inst['paid_amount'] as int) - (a['amount'] as int);
          if (newPaid < 0) {
            throw const AppException('تعذّر العكس: عدم اتساق في مدفوعات القسط');
          }
          await txn.update(
            'installments',
            {
              'paid_amount': newPaid,
              'status': InstallmentCalculator.statusFor(
                amount: inst['amount'] as int,
                paid: newPaid,
                dueDate: inst['due_date'] as String,
                today: _today,
              ).code,
              'updated_at': now,
            },
            where: 'id = ?',
            whereArgs: [instId],
          );
        }
        await txn.update(
          'payment_allocations',
          {'reversed_at': now},
          where: 'id = ?',
          whereArgs: [a['id']],
        );
      }

      await txn.update(
        'payments',
        {
          'status': 'reversed',
          'reversal_reason': trimmed,
          'reversed_at': now,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [paymentId],
      );
      await txn.update(
        'receipts',
        {'status': 'cancelled'},
        where: 'payment_id = ?',
        whereArgs: [paymentId],
      );
      await writeAudit(
        txn,
        entity: 'payment',
        entityId: paymentId,
        action: 'reverse',
        details: {'reason': trimmed, 'amount': p.first['amount']},
        actorId: actorId,
      );
    });
  }

  List<AllocationShare> _validateManual(
    int amount,
    List<InstallmentDue> dues,
    Map<int, int> manual,
  ) {
    final remainingById = {for (final d in dues) d.id: d.remaining};
    var total = 0;
    final out = <AllocationShare>[];
    for (final e in manual.entries) {
      final share = e.value;
      if (share <= 0) {
        throw const AppException('مبلغ التخصيص يجب أن يكون أكبر من صفر');
      }
      final rem = remainingById[e.key];
      if (rem == null) {
        throw const AppException('القسط المحدد غير صالح للتخصيص');
      }
      if (share > rem) {
        throw const AppException('التخصيص يتجاوز المتبقي من القسط');
      }
      total += share;
      out.add(AllocationShare(e.key, share));
    }
    if (total > amount) {
      throw const AppException('مجموع التخصيص يتجاوز قيمة الدفعة');
    }
    return out;
  }

  /// رقم يدوي (يجب ألا يتكرر) أو توليد تسلسلي R-000001 من app_settings.
  Future<String> _resolveReceiptNo(Transaction txn, String? provided) async {
    final manual = provided?.trim() ?? '';
    if (manual.isNotEmpty) {
      if (await _receiptExists(txn, manual)) {
        throw const AppException('رقم السند مستخدم مسبقًا');
      }
      return manual;
    }
    while (true) {
      final r = await txn.query(
        'app_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: [AppConstants.settingReceiptSeq],
        limit: 1,
      );
      final current = r.isEmpty ? 0 : int.tryParse('${r.first['value']}') ?? 0;
      final next = current + 1;
      await txn.insert(
        'app_settings',
        {'key': AppConstants.settingReceiptSeq, 'value': '$next'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final candidate = 'R-${next.toString().padLeft(6, '0')}';
      if (!await _receiptExists(txn, candidate)) return candidate;
    }
  }

  Future<bool> _receiptExists(DatabaseExecutor ex, String no) async {
    final r = await ex.query(
      'payments',
      columns: ['id'],
      where: 'receipt_no = ?',
      whereArgs: [no],
      limit: 1,
    );
    return r.isNotEmpty;
  }

  String _uuid() {
    final rnd = Random.secure();
    return List<String>.generate(
      16,
      (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
