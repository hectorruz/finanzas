import 'package:flutter/material.dart';

import 'report_service.dart';

/// Tipo de tarjeta de la portada: decide dónde y cómo se agrupa en el
/// renderizado (las KPI van en la rejilla superior; gráficos y análisis se
/// apilan debajo, en el orden elegido). Excel no soporta gráficos, así que
/// [chart] se ignora al generar el `.xlsx` (ver `report_excel.dart`).
enum ReportCoverCardKind { kpi, chart, block }

/// Descriptor de una tarjeta disponible para la portada personalizable del
/// informe (PDF y Excel comparten el mismo catálogo de claves).
class ReportCoverCard {
  const ReportCoverCard(this.key, this.label, this.icon, this.kind);

  final String key;
  final String label;
  final IconData icon;
  final ReportCoverCardKind kind;
}

/// Todas las tarjetas disponibles, en el orden en que se ofrecen en el editor.
/// El valor por defecto ([kDefaultReportCoverCards], en `report_service.dart`)
/// reproduce la portada fija que había antes de hacerla personalizable.
const List<ReportCoverCard> kReportCoverCatalog = [
  ReportCoverCard(
      'kpiIncome', 'Ingresos', Icons.south_west, ReportCoverCardKind.kpi),
  ReportCoverCard(
      'kpiExpense', 'Gastos', Icons.north_east, ReportCoverCardKind.kpi),
  ReportCoverCard('kpiNet', 'Neto', Icons.balance, ReportCoverCardKind.kpi),
  ReportCoverCard('kpiSavingsRate', 'Ahorro (%)', Icons.savings_outlined,
      ReportCoverCardKind.kpi),
  ReportCoverCard('kpiBiggestExpense', 'Mayor gasto', Icons.trending_down,
      ReportCoverCardKind.kpi),
  ReportCoverCard('kpiTopCategory', 'Categoría con más gasto',
      Icons.category_outlined, ReportCoverCardKind.kpi),
  ReportCoverCard('kpiTopAccount', 'Cuenta más usada',
      Icons.account_balance_wallet_outlined, ReportCoverCardKind.kpi),
  ReportCoverCard('chartCategoryPie', 'Gráfico circular · categorías',
      Icons.pie_chart_outline, ReportCoverCardKind.chart),
  ReportCoverCard('chartEvolutionBar', 'Gráfico de barras · evolución',
      Icons.bar_chart, ReportCoverCardKind.chart),
  ReportCoverCard('blockComparison', 'Comparativa con el periodo anterior',
      Icons.compare_arrows, ReportCoverCardKind.block),
  ReportCoverCard('blockAverages', 'Medias y récords', Icons.query_stats,
      ReportCoverCardKind.block),
  ReportCoverCard('blockTopCategories', 'Top categorías de gasto',
      Icons.leaderboard_outlined, ReportCoverCardKind.block),
];

/// Busca el descriptor de una clave (o `null` si es desconocida — versión
/// antigua tras quitar un tipo de tarjeta).
ReportCoverCard? reportCoverCardByKey(String key) {
  for (final c in kReportCoverCatalog) {
    if (c.key == key) return c;
  }
  return null;
}

/// Etiqueta legible de una clave (fallback a la propia clave).
String reportCoverCardLabel(String key) =>
    reportCoverCardByKey(key)?.label ?? key;
