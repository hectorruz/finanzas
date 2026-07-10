import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money.dart';
import '../analytics/web_analytics.dart';

/// Formato compacto de euros para ejes ("1,2k", "340"). Con [hide] devuelve '·'.
String _compactEuros(double euros, {bool hide = false}) {
  if (hide) return '·';
  final a = euros.abs();
  if (a >= 1000) return '${(euros / 1000).toStringAsFixed(a >= 10000 ? 0 : 1)}k';
  return euros.toStringAsFixed(0);
}

/// Donut de reparto por categoría, con leyenda. Agrupa la cola en "Otros".
class WebDonutChart extends StatelessWidget {
  const WebDonutChart({
    super.key,
    required this.slices,
    this.hideAmounts = false,
    this.maxSlices = 6,
  });

  final List<CategorySlice> slices;
  final bool hideAmounts;
  final int maxSlices;

  @override
  Widget build(BuildContext context) {
    if (slices.isEmpty || slices.every((s) => s.totalCents == 0)) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('Sin datos en el periodo.')),
      );
    }
    // Top N + "Otros".
    final shown = slices.take(maxSlices).toList();
    final restTotal =
        slices.skip(maxSlices).fold<int>(0, (s, e) => s + e.totalCents);
    final entries = [
      ...shown.map((s) => (label: s.label, color: Color(s.colorValue), cents: s.totalCents)),
      if (restTotal > 0)
        (label: 'Otros', color: const Color(0xFF9E9E9E), cents: restTotal),
    ];
    final total = entries.fold<int>(0, (s, e) => s + e.cents);

    return SizedBox(
      height: 220,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 2,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 48,
                sections: [
                  for (final e in entries)
                    PieChartSectionData(
                      value: e.cents.toDouble(),
                      color: e.color,
                      radius: 46,
                      showTitle: false,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                              color: e.color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(e.label,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          hideAmounts
                              ? '••••'
                              : '${(e.cents * 100 / total).round()}%',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Theme.of(context).colorScheme.outline),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Barras de ingresos vs. gastos por mes.
class WebIncomeExpenseBars extends StatelessWidget {
  const WebIncomeExpenseBars({
    super.key,
    required this.buckets,
    this.hideAmounts = false,
  });

  final List<MonthBucket> buckets;
  final bool hideAmounts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxCents = buckets.fold<int>(
        1,
        (m, b) => [m, b.incomeCents, b.expenseCents]
            .reduce((a, c) => a > c ? a : c));
    final maxEuros = maxCents / 100;

    return SizedBox(
      height: 240,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxEuros * 1.15,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: scheme.outlineVariant, strokeWidth: 0.5),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) => Text(
                  _compactEuros(value, hide: hideAmounts),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= buckets.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      DateFormat('MMM', 'es').format(buckets[i].month),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < buckets.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: buckets[i].incomeCents / 100,
                    color: Colors.green,
                    width: 9,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
                  BarChartRodData(
                    toY: buckets[i].expenseCents / 100,
                    color: scheme.error,
                    width: 9,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Línea de evolución del balance total.
class WebBalanceLine extends StatelessWidget {
  const WebBalanceLine({
    super.key,
    required this.points,
    this.hideAmounts = false,
  });

  final List<BalancePoint> points;
  final bool hideAmounts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (points.length < 2) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('Sin histórico suficiente.')),
      );
    }
    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].balanceCents / 100),
    ];
    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY).abs() * 0.1) + 1;

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minY: minY - pad,
          maxY: maxY + pad,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: scheme.outlineVariant, strokeWidth: 0.5),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (value, meta) => Text(
                  _compactEuros(value, hide: hideAmounts),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: (points.length / 4).ceilToDouble(),
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= points.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      DateFormat('d MMM', 'es').format(points[i].date),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              barWidth: 2.5,
              color: scheme.primary,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: scheme.primary.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Etiqueta de importe formateada respetando privacidad, para leyendas fuera de
/// un `ConsumerWidget`.
String formatEurosOrHidden(int cents, {required bool hide}) =>
    hide ? '••••' : Money(cents).format();
