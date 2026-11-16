import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/settings/presentation/more_page.dart';
import '../features/shell/presentation/home_shell.dart';
import '../shared/widgets/section_placeholder_page.dart';

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/home',
              builder: (c, s) => const SectionPlaceholderPage(
                  title: 'الرئيسية', icon: Icons.dashboard_outlined, phase: 3),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/students',
              builder: (c, s) => const SectionPlaceholderPage(
                  title: 'الطلاب', icon: Icons.groups_outlined, phase: 3),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/collection',
              builder: (c, s) => const SectionPlaceholderPage(
                  title: 'التحصيل', icon: Icons.payments_outlined, phase: 4),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/attendance',
              builder: (c, s) => const SectionPlaceholderPage(
                  title: 'الحضور', icon: Icons.fact_check_outlined, phase: 5),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/more', builder: (c, s) => const MorePage()),
          ]),
        ],
      ),
    ],
  );
}
