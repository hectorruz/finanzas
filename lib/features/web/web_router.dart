import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'pages/web_accounts_page.dart';
import 'pages/web_calendar_page.dart';
import 'pages/web_categories_page.dart';
import 'pages/web_dashboard_page.dart';
import 'pages/web_goals_page.dart';
import 'pages/web_movements_page.dart';
import 'pages/web_receipts_page.dart';
import 'pages/web_recurring_page.dart';
import 'pages/web_reports_page.dart';
import 'pages/web_settings_page.dart';
import 'web_shell.dart';

/// Rutas de la webapp de escritorio (URLs reales por sección → botón atrás del
/// navegador y deep-links).
class WebRoutes {
  static const dashboard = '/dashboard';
  static const movements = '/movimientos';
  static const accounts = '/cuentas';
  static const categories = '/categorias';
  static const recurring = '/recurrentes';
  static const goals = '/objetivos';
  static const receipts = '/tickets';
  static const reports = '/informes';
  static const calendar = '/calendario';
  static const settings = '/ajustes';
}

/// Descriptor de una sección de la barra lateral.
class WebNavItem {
  const WebNavItem(this.route, this.label, this.icon, this.group);
  final String route;
  final String label;
  final IconData icon;

  /// Grupo para agrupar visualmente en la barra lateral.
  final String group;
}

/// Secciones de navegación, en orden y agrupadas.
const List<WebNavItem> webNavItems = [
  WebNavItem(WebRoutes.dashboard, 'Panel', Icons.dashboard_outlined, 'General'),
  WebNavItem(WebRoutes.movements, 'Movimientos', Icons.swap_vert, 'General'),
  WebNavItem(WebRoutes.receipts, 'Tickets', Icons.receipt_long_outlined, 'General'),
  WebNavItem(WebRoutes.accounts, 'Cuentas', Icons.account_balance_outlined, 'Gestión'),
  WebNavItem(WebRoutes.categories, 'Categorías', Icons.category_outlined, 'Gestión'),
  WebNavItem(WebRoutes.recurring, 'Recurrentes', Icons.autorenew, 'Gestión'),
  WebNavItem(WebRoutes.goals, 'Objetivos', Icons.flag_outlined, 'Gestión'),
  WebNavItem(WebRoutes.reports, 'Informes', Icons.insights_outlined, 'Análisis'),
  WebNavItem(WebRoutes.calendar, 'Calendario', Icons.calendar_month_outlined,
      'Análisis'),
  WebNavItem(WebRoutes.settings, 'Ajustes', Icons.settings_outlined, 'Sistema'),
];

/// Construye el router. Se cachea en un provider para no recrearlo en cada
/// rebuild (ver `webRouterProvider`).
GoRouter buildWebRouter() {
  Widget page(Widget child) => child;
  return GoRouter(
    initialLocation: WebRoutes.dashboard,
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            WebShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
              path: WebRoutes.dashboard,
              builder: (_, __) => page(const WebDashboardPage())),
          GoRoute(
              path: WebRoutes.movements,
              builder: (_, __) => page(const WebMovementsPage())),
          GoRoute(
              path: WebRoutes.receipts,
              builder: (_, __) => page(const WebReceiptsPage())),
          GoRoute(
              path: WebRoutes.accounts,
              builder: (_, __) => page(const WebAccountsPage())),
          GoRoute(
              path: WebRoutes.categories,
              builder: (_, __) => page(const WebCategoriesPage())),
          GoRoute(
              path: WebRoutes.recurring,
              builder: (_, __) => page(const WebRecurringPage())),
          GoRoute(
              path: WebRoutes.goals,
              builder: (_, __) => page(const WebGoalsPage())),
          GoRoute(
              path: WebRoutes.reports,
              builder: (_, __) => page(const WebReportsPage())),
          GoRoute(
              path: WebRoutes.calendar,
              builder: (_, __) => page(const WebCalendarPage())),
          GoRoute(
              path: WebRoutes.settings,
              builder: (_, __) => page(const WebSettingsPage())),
        ],
      ),
    ],
  );
}
