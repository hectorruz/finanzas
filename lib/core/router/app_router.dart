import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/enums.dart';
import '../../features/accounts/account_editor_screen.dart';
import '../../features/accounts/accounts_screen.dart';
import '../../features/categories/categories_screen.dart';
import '../../features/home_shell.dart';
import '../../features/movements/movement_editor_screen.dart';
import '../../features/movements/recurring_editor_screen.dart';
import '../../features/movements/recurring_screen.dart';
import '../../features/receipts/receipt_scan_screen.dart';
import '../../features/reports/report_screen.dart';
import '../../features/settings/dashboard_config_screen.dart';
import '../../features/settings/nav_config_screen.dart';
import '../../features/sync/sync_review_screen.dart';

/// Rutas con nombre de la app.
class Routes {
  static const home = '/';
  static const movementEditor = '/movement';
  static const accounts = '/accounts';
  static const accountEditor = '/account';
  static const categories = '/categories';
  static const recurring = '/recurring';
  static const recurringEditor = '/recurring/edit';
  static const receiptScan = '/receipt/scan';
  static const dashboardConfig = '/settings/dashboard';
  static const navConfig = '/settings/nav';
  static const reports = '/reports';
  static const syncReview = '/settings/sync/review';
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.home,
    routes: [
      GoRoute(
        path: Routes.home,
        builder: (_, __) => const HomeShell(),
      ),
      GoRoute(
        path: Routes.movementEditor,
        builder: (_, state) {
          final extra = state.extra;
          return MovementEditorScreen(
            transactionId: extra is int ? extra : null,
            initialType: extra is TransactionType ? extra : null,
          );
        },
      ),
      GoRoute(
        path: Routes.accounts,
        builder: (_, __) => const AccountsScreen(),
      ),
      GoRoute(
        path: Routes.accountEditor,
        builder: (_, state) {
          final extra = state.extra;
          if (extra is AccountEditorArgs) {
            return AccountEditorScreen(
              accountId: extra.accountId,
              parentId: extra.parentId,
            );
          }
          return AccountEditorScreen(accountId: extra is int ? extra : null);
        },
      ),
      GoRoute(
        path: Routes.categories,
        builder: (_, __) => const CategoriesScreen(),
      ),
      GoRoute(
        path: Routes.recurring,
        builder: (_, __) => const RecurringScreen(),
      ),
      GoRoute(
        path: Routes.recurringEditor,
        builder: (_, state) =>
            RecurringEditorScreen(ruleId: _intExtra(state)),
      ),
      GoRoute(
        path: Routes.receiptScan,
        builder: (_, state) => ReceiptScanScreen(receiptId: _intExtra(state)),
      ),
      GoRoute(
        path: Routes.dashboardConfig,
        builder: (_, __) => const DashboardConfigScreen(),
      ),
      GoRoute(
        path: Routes.navConfig,
        builder: (_, __) => const NavConfigScreen(),
      ),
      GoRoute(
        path: Routes.reports,
        builder: (_, __) => const ReportScreen(),
      ),
      GoRoute(
        path: Routes.syncReview,
        builder: (_, state) =>
            SyncReviewScreen(args: state.extra as SyncReviewArgs),
      ),
    ],
  );
});

/// Extrae un id entero opcional pasado por `extra`.
int? _intExtra(GoRouterState state) => state.extra as int?;
