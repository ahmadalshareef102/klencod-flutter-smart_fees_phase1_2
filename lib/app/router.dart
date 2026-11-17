import 'package:go_router/go_router.dart';

import '../features/attendance/presentation/attendance_page.dart';
import '../features/batches/presentation/batch_form_page.dart';
import '../features/expenses/presentation/expense_form_page.dart';
import '../features/expenses/presentation/expenses_page.dart';
import '../features/institute/presentation/institute_page.dart';
import '../features/reports/presentation/reports_page.dart';
import '../features/batches/presentation/batches_page.dart';
import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/shell/presentation/home_shell.dart';
import '../features/students/presentation/student_detail_page.dart';
import '../features/students/presentation/student_form_page.dart';
import '../features/students/presentation/students_page.dart';

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/home', builder: (c, s) => const DashboardPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/batches', builder: (c, s) => const BatchesPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/settings', builder: (c, s) => const SettingsPage()),
          ]),
        ],
      ),
      // الشاشات الداخلية بملء الشاشة (بدون شريط التنقل السفلي).
      GoRoute(path: '/batches/new', builder: (c, s) => const BatchFormPage()),
      GoRoute(path: '/expenses', builder: (c, s) => const ExpensesPage()),
      GoRoute(path: '/expenses/new', builder: (c, s) => const ExpenseFormPage()),
      GoRoute(path: '/attendance', builder: (c, s) => const AttendancePage()),
      GoRoute(path: '/reports', builder: (c, s) => const ReportsPage()),
      GoRoute(path: '/institute', builder: (c, s) => const InstitutePage()),
      GoRoute(
        path: '/students',
        builder: (c, s) => StudentsPage(
            initialBatchId: int.tryParse(s.uri.queryParameters['batch'] ?? '')),
      ),
      // مسار /students/new يجب أن يسبق /students/:id.
      GoRoute(path: '/students/new', builder: (c, s) => const StudentFormPage()),
      GoRoute(
        path: '/students/:id',
        builder: (c, s) =>
            StudentDetailPage(studentId: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/students/:id/edit',
        builder: (c, s) =>
            StudentFormPage(studentId: int.parse(s.pathParameters['id']!)),
      ),
    ],
  );
}
