import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/enums.dart';
import '../../features/accounts/account_editor_screen.dart';
import '../../features/accounts/accounts_screen.dart';
import '../../features/categories/categories_screen.dart';
import '../../features/home_shell.dart';
import '../../features/investments/holding_editor_screen.dart';
import '../../features/investments/holding_detail_screen.dart';
import '../../features/movements/movement_editor_screen.dart';
import '../../features/movements/recurring_editor_screen.dart';
import '../../features/movements/recurring_screen.dart';
import '../../features/receipts/receipt_scan_screen.dart';
import '../../features/settings/dashboard_config_screen.dart';

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
  static const holdingEditor = '/holding';
  static const holdingDetail = '/holding/detail';
  static const dashboardConfig = '/settings/dashboard';
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
        builder: (_, state) =>
            AccountEditorScreen(accountId: _intExtra(state)),
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
        builder: (_, __) => const ReceiptScanScreen(),
      ),
      GoRoute(
        path: Routes.holdingEditor,
        builder: (_, state) =>
            HoldingEditorScreen(holdingId: _intExtra(state)),
      ),
      GoRoute(
        path: Routes.holdingDetail,
        builder: (_, state) {
          final id = _intExtra(state);
          if (id == null) return const HomeShell();
          return HoldingDetailScreen(holdingId: id);
        },
      ),
      GoRoute(
        path: Routes.dashboardConfig,
        builder: (_, __) => const DashboardConfigScreen(),
      ),
    ],
  );
});

/// Extrae un id entero opcional pasado por `extra`.
int? _intExtra(GoRouterState state) => state.extra as int?;
