import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/models/enums.dart';
import '../analytics/web_analytics.dart';
import '../web_download.dart';
import '../web_providers.dart';
import '../widgets/web_charts.dart';
import '../widgets/web_money_text.dart';
import '../widgets/web_ui.dart';
import 'web_account_compare_view.dart';

/// Informes: analítica interactiva recalculada en el navegador + descarga del
/// PDF/Excel generado por el móvil (mismo `ReportService`).
class WebReportsPage extends ConsumerStatefulWidget {
  const WebReportsPage({super.key});

  @override
  ConsumerState<WebReportsPage> createState() => _WebReportsPageState();
}

class _WebReportsPageState extends ConsumerState<WebReportsPage> {
  late DateTime _from;
  late DateTime _to;
  String _flow = 'expense';
  String? _downloading;

  final _sections = <String, bool>{
    'balance': true,
    'evolution': true,
    'movements': true,
    'incomeByCategory': false,
    'expenseByAccount': false,
    'topConcepts': false,
    'comparison': false,
    'averages': false,
  };

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month + 1, 0);
  }

  void _preset(DateTime from, DateTime to) => setState(() {
        _from = from;
        _to = to;
      });

  Future<void> _download(String format) async {
    setState(() => _downloading = format);
    try {
      final config = <String, dynamic>{
        'from': _from.toIso8601String(),
        'to': _to.toIso8601String(),
        'flow': _flow,
        'dashboardPage': true,
        ..._sections,
      };
      final Uint8List bytes =
          await ref.read(webClientProvider)!.report(format, config);
      final name =
          'informe_${DateFormat('yyyyMMdd').format(_from)}_${DateFormat('yyyyMMdd').format(_to)}';
      if (format == 'pdf') {
        webDownloadBytes(bytes, '$name.pdf', 'application/pdf');
      } else {
        webDownloadBytes(bytes, '$name.xlsx',
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error al generar: $e')));
      }
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final txns = ref.watch(webAllTransactionsProvider).valueOrNull ?? const [];
    final categories = ref.watch(webCategoriesByIdProvider);
    final hide = ref.watch(webHideAmountsProvider);

    final fromDay = DateTime(_from.year, _from.month, _from.day);
    final toDay = DateTime(_to.year, _to.month, _to.day, 23, 59, 59);
    final summary = periodSummary(txns, from: fromDay, to: toDay);

    // Periodo anterior de igual longitud (para comparativa).
    final lengthDays = toDay.difference(fromDay).inDays + 1;
    final prevTo = fromDay.subtract(const Duration(seconds: 1));
    final prevFrom = fromDay.subtract(Duration(days: lengthDays));
    final prevSummary = periodSummary(txns, from: prevFrom, to: prevTo);

    final buckets = monthlyTotalsBetween(txns, from: fromDay, to: toDay);
    final breakdown = categoryBreakdown(
      txns,
      categories,
      type: _flow == 'income' ? TransactionType.income : TransactionType.expense,
      from: fromDay,
      to: toDay.add(const Duration(seconds: 1)),
    );
    final days = lengthDays < 1 ? 1 : lengthDays;
    final avgExpensePerDay = summary.expenseCents ~/ days;

    return WebPage(
      title: 'Informes',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _controls(context),
          const SizedBox(height: 16),
          // KPIs
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 520 ? 2 : 1);
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 2.3,
              children: [
                WebKpiCard(
                    label: 'Ingresos',
                    icon: Icons.south_west,
                    valueColor: Colors.green,
                    value: WebMoneyText(summary.incomeCents),
                    trailing: _delta(context, summary.incomeCents,
                        prevSummary.incomeCents,
                        goodWhenUp: true)),
                WebKpiCard(
                    label: 'Gastos',
                    icon: Icons.north_east,
                    valueColor: Theme.of(context).colorScheme.error,
                    value: WebMoneyText(summary.expenseCents),
                    trailing: _delta(context, summary.expenseCents,
                        prevSummary.expenseCents,
                        goodWhenUp: false)),
                WebKpiCard(
                    label: 'Balance',
                    icon: Icons.balance,
                    valueColor: summary.netCents >= 0
                        ? Colors.green
                        : Theme.of(context).colorScheme.error,
                    value: WebMoneyText(summary.netCents, signed: true)),
                WebKpiCard(
                    label: 'Gasto medio/día',
                    icon: Icons.today,
                    value: WebMoneyText(avgExpensePerDay)),
              ],
            );
          }),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth >= 900;
            final donut = _card(
                context,
                _flow == 'income'
                    ? 'Ingresos por categoría'
                    : 'Gastos por categoría',
                WebDonutChart(slices: breakdown, hideAmounts: hide));
            final bars = _card(context, 'Ingresos vs. gastos por mes',
                WebIncomeExpenseBars(buckets: buckets, hideAmounts: hide));
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: donut),
                  const SizedBox(width: 16),
                  Expanded(child: bars),
                ],
              );
            }
            return Column(children: [donut, const SizedBox(height: 16), bars]);
          }),
          const SizedBox(height: 16),
          Text('Comparativa de cuentas',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          WebAccountCompareView(from: fromDay, to: toDay),
          const SizedBox(height: 16),
          _downloadCard(context),
        ],
      ),
    );
  }

  Widget _controls(BuildContext context) {
    final df = DateFormat('d MMM yyyy', 'es');
    final now = DateTime.now();
    return WebCard(
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ActionChip(
            avatar: const Icon(Icons.date_range, size: 18),
            label: Text('${df.format(_from)} – ${df.format(_to)}'),
            onPressed: () async {
              final r = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                initialDateRange: DateTimeRange(start: _from, end: _to),
              );
              if (r != null) _preset(r.start, r.end);
            },
          ),
          ActionChip(
              label: const Text('Este mes'),
              onPressed: () => _preset(DateTime(now.year, now.month, 1),
                  DateTime(now.year, now.month + 1, 0))),
          ActionChip(
              label: const Text('Mes pasado'),
              onPressed: () => _preset(DateTime(now.year, now.month - 1, 1),
                  DateTime(now.year, now.month, 0))),
          ActionChip(
              label: const Text('Este año'),
              onPressed: () => _preset(
                  DateTime(now.year, 1, 1), DateTime(now.year, 12, 31))),
          ActionChip(
              label: const Text('12 meses'),
              onPressed: () => _preset(DateTime(now.year, now.month - 11, 1),
                  DateTime(now.year, now.month + 1, 0))),
          const SizedBox(width: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'expense', label: Text('Gastos')),
              ButtonSegment(value: 'income', label: Text('Ingresos')),
            ],
            selected: {_flow},
            onSelectionChanged: (s) => setState(() => _flow = s.first),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, String title, Widget child) {
    return WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _downloadCard(BuildContext context) {
    const labels = {
      'balance': 'Balance',
      'evolution': 'Evolución',
      'movements': 'Movimientos',
      'incomeByCategory': 'Ingreso por categoría',
      'expenseByAccount': 'Gasto por cuenta',
      'topConcepts': 'Dónde más gastas',
      'comparison': 'Comparativa',
      'averages': 'Medias y récords',
    };
    return WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Descargar informe',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Lo genera tu móvil con todas las secciones elegidas.',
              style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final e in labels.entries)
                FilterChip(
                  label: Text(e.value),
                  selected: _sections[e.key] ?? false,
                  onSelected: (v) => setState(() => _sections[e.key] = v),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                icon: _downloading == 'pdf'
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.picture_as_pdf),
                label: const Text('Descargar PDF'),
                onPressed: _downloading != null ? null : () => _download('pdf'),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                icon: _downloading == 'excel'
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.table_chart),
                label: const Text('Descargar Excel'),
                onPressed:
                    _downloading != null ? null : () => _download('excel'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget? _delta(BuildContext context, int current, int previous,
      {required bool goodWhenUp}) {
    final change = monthOverMonthChange(current, previous);
    if (change == null) return null;
    final up = change > 0;
    final good = up == goodWhenUp;
    final color = good ? Colors.green : Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? Icons.arrow_upward : Icons.arrow_downward,
              size: 12, color: color),
          Text('${(change.abs() * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
