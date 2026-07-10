import 'package:flutter/material.dart';

/// Catálogo de tarjetas del panel de la **webapp de escritorio**. Es
/// independiente de las tarjetas del inicio del móvil (`DashboardCardType`):
/// aquí hay más tipos y la web tiene su propia configuración
/// (`AppSettings.webDashboardCards`, que viaja por `/api/settings`).
///
/// Cada tarjeta tiene una `key` estable (la que se guarda), una etiqueta y un
/// icono para el editor, y si es un KPI (tarjeta métrica pequeña que va en la
/// rejilla superior) o un bloque (gráfica/lista a ancho completo).
class WebDashboardCard {
  const WebDashboardCard(this.key, this.label, this.icon, {this.isKpi = false});

  final String key;
  final String label;
  final IconData icon;
  final bool isKpi;
}

/// Todas las tarjetas disponibles, en el orden en que se ofrecen en el editor.
const List<WebDashboardCard> kWebDashboardCatalog = [
  WebDashboardCard('kpiTotalBalance', 'Balance total (KPI)',
      Icons.account_balance_wallet_outlined,
      isKpi: true),
  WebDashboardCard('kpiIncome', 'Ingresos del mes (KPI)', Icons.south_west,
      isKpi: true),
  WebDashboardCard('kpiExpense', 'Gastos del mes (KPI)', Icons.north_east,
      isKpi: true),
  WebDashboardCard('kpiSavings', 'Ahorro del mes (KPI)',
      Icons.savings_outlined,
      isKpi: true),
  WebDashboardCard('kpiSavingsRate', 'Tasa de ahorro (KPI)', Icons.percent,
      isKpi: true),
  WebDashboardCard(
      'categoryDonut', 'Gasto por categoría', Icons.donut_large_outlined),
  WebDashboardCard(
      'incomeExpenseBars', 'Ingresos vs. gastos', Icons.bar_chart_outlined),
  WebDashboardCard(
      'balanceLine', 'Evolución del balance (90 días)', Icons.show_chart),
  WebDashboardCard(
      'topCategories', 'Top categorías de gasto', Icons.leaderboard_outlined),
  WebDashboardCard(
      'upcomingRecurring', 'Próximos recurrentes', Icons.event_repeat),
  WebDashboardCard(
      'recentMovements', 'Últimos movimientos', Icons.receipt_long_outlined),
  WebDashboardCard('goals', 'Objetivos', Icons.flag_outlined),
  WebDashboardCard('accounts', 'Cuentas', Icons.account_balance_outlined),
];

/// Layout por defecto (cuando `webDashboardCards` está vacío): equivale al panel
/// clásico + los KPIs sueltos.
const List<String> kDefaultWebDashboard = [
  'kpiTotalBalance',
  'kpiIncome',
  'kpiExpense',
  'kpiSavings',
  'categoryDonut',
  'incomeExpenseBars',
  'balanceLine',
  'recentMovements',
  'goals',
  'accounts',
];

/// Busca el descriptor de una clave (o `null` si es desconocida).
WebDashboardCard? webCardByKey(String key) {
  for (final c in kWebDashboardCatalog) {
    if (c.key == key) return c;
  }
  return null;
}

/// Etiqueta legible de una clave (fallback a la propia clave).
String webCardLabel(String key) => webCardByKey(key)?.label ?? key;

/// Si la clave corresponde a un KPI (rejilla superior).
bool webCardIsKpi(String key) => webCardByKey(key)?.isKpi ?? false;
