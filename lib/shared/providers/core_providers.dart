import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/helpers/date_range.dart';
import '../../features/attendance/data/attendance_repository.dart';
import '../../features/expenses/data/expense_repository.dart';
import '../../features/institute/data/institute_repository.dart';
import '../../features/receipts/data/receipt_repository.dart';
import '../../features/reports/data/report_repository.dart';
import '../../features/batches/data/batch_repository.dart';
import '../../features/dashboard/data/dashboard_repository.dart';
import '../../features/fees/data/fee_plan_repository.dart';
import '../../features/installments/data/accrual_service.dart';
import '../../features/payments/data/payment_repository.dart';
import '../../features/settings/data/settings_repository.dart';
import '../../features/students/data/student_repository.dart';

/// يُستبدل في main.dart بعد فتح القاعدة.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('يجب تجاوز appDatabaseProvider في main'),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(appDatabaseProvider).db),
);

final paymentRepositoryProvider = Provider<PaymentRepository>(
  (ref) => PaymentRepository(ref.watch(appDatabaseProvider).db),
);

final feePlanRepositoryProvider = Provider<FeePlanRepository>(
  (ref) => FeePlanRepository(ref.watch(appDatabaseProvider).db),
);

final batchRepositoryProvider = Provider<BatchRepository>(
  (ref) => BatchRepository(ref.watch(appDatabaseProvider).db),
);

final studentRepositoryProvider = Provider<StudentRepository>(
  (ref) => StudentRepository(
    ref.watch(appDatabaseProvider).db,
    ref.watch(feePlanRepositoryProvider),
    ref.watch(paymentRepositoryProvider),
  ),
);

final accrualServiceProvider = Provider<AccrualService>(
  (ref) => AccrualService(ref.watch(appDatabaseProvider).db),
);

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(ref.watch(appDatabaseProvider).db),
);

/// عدّاد يُزاد بعد أي عملية كتابة فتُعاد قراءة كل الشاشات المعتمدة عليه.
/// هكذا تتحدث لوحة التحكم تلقائيًا عند إضافة أو تعديل أو إلغاء أي عملية.
final dataRevisionProvider =
    NotifierProvider<DataRevision, int>(DataRevision.new);

class DataRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  ref.watch(dataRevisionProvider);
  await ref.read(accrualServiceProvider).run();
  return ref.read(dashboardRepositoryProvider).load();
});

final batchesProvider = FutureProvider<List<BatchSummary>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.read(batchRepositoryProvider).list();
});

/// معاملات قائمة الطلاب.
class StudentQuery {
  const StudentQuery({this.text = '', this.batchId});

  final String text;
  final int? batchId;

  @override
  bool operator ==(Object other) =>
      other is StudentQuery && other.text == text && other.batchId == batchId;

  @override
  int get hashCode => Object.hash(text, batchId);
}

final studentsProvider =
    FutureProvider.family<List<StudentRow>, StudentQuery>((ref, q) {
  ref.watch(dataRevisionProvider);
  return ref
      .read(studentRepositoryProvider)
      .list(query: q.text, batchId: q.batchId);
});

final studentDetailProvider =
    FutureProvider.family<StudentDetail?, int>((ref, id) {
  ref.watch(dataRevisionProvider);
  return ref.read(studentRepositoryProvider).detail(id);
});

/// وضع الثيم المحفوظ وقت الإقلاع (يُستبدل في main).
final initialThemeModeProvider = Provider<ThemeMode>((ref) => ThemeMode.system);

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.watch(initialThemeModeProvider);

  /// يغيّر الوضع فورًا ثم يحفظه محليًا.
  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await ref.read(settingsRepositoryProvider).setThemeMode(mode);
  }
}

// ---------------------------------------------------------------- المصروفات

final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => ExpenseRepository(ref.watch(appDatabaseProvider).db),
);

final expensesProvider =
    FutureProvider.family<ExpenseSummary, DateRange>((ref, range) {
  ref.watch(dataRevisionProvider);
  return ref.read(expenseRepositoryProvider).summary(range);
});

final expenseCategoriesProvider = FutureProvider<List<ExpenseCategory>>(
  (ref) => ref.read(expenseRepositoryProvider).categories(),
);

// ------------------------------------------------------------------- المعهد

final instituteRepositoryProvider = Provider<InstituteRepository>(
  (ref) => InstituteRepository(ref.watch(appDatabaseProvider).db),
);

final instituteProvider = FutureProvider<InstituteInfo?>(
  (ref) => ref.read(instituteRepositoryProvider).get(),
);

// -------------------------------------------------------------------- الحضور

final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => AttendanceRepository(ref.watch(appDatabaseProvider).db),
);

class RosterKey {
  const RosterKey(this.batchId, this.date);

  final int batchId;
  final String date;

  @override
  bool operator ==(Object other) =>
      other is RosterKey && other.batchId == batchId && other.date == date;

  @override
  int get hashCode => Object.hash(batchId, date);
}

final rosterProvider =
    FutureProvider.family<List<RosterEntry>, RosterKey>((ref, k) {
  ref.watch(dataRevisionProvider);
  return ref.read(attendanceRepositoryProvider).roster(k.batchId, k.date);
});

// ------------------------------------------------------- السندات والتقارير

final receiptRepositoryProvider = Provider<ReceiptRepository>(
  (ref) => ReceiptRepository(
    ref.watch(appDatabaseProvider).db,
    ref.watch(instituteRepositoryProvider),
  ),
);

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(
    ref.watch(appDatabaseProvider).db,
    ref.watch(attendanceRepositoryProvider),
  ),
);
