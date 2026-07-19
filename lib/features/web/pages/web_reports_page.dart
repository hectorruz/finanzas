import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/models/enums.dart';
import '../../../data/report_config.dart';
import '../../../shared/widgets/report_cover_cards_editor.dart';
import '../analytics/web_analytics.dart';
import '../web_download.dart';
import '../web_models.dart';
import '../web_providers.dart';
import '../widgets/web_charts.dart';
import '../widgets/web_money_text.dart';
import '../widgets/web_ui.dart';
import 'web_account_compare_view.dart';

/// Informes: analítica interactiva recalculada en el navegador + descarga del
/// PDF/Excel generado por el móvil (mismo `ReportService`).
///
/// Las opciones de descarga usan el mismo `ReportConfig` que la app (guardado
/// en `AppSettings.reportConfig`, que ya viaja por `/api/settings`), así que
/// son exactamente las mismas en el móvil y en la webapp — ver
/// "Building the APK" / la nota de CLAUDE.md sobre mantener la web al día.
class WebReportsPage extends ConsumerStatefulWidget {
  const WebReportsPage({super.key});

  @override
  ConsumerState<WebReportsPage> createState() => _WebReportsPageState();
}

class _WebReportsPageState extends ConsumerState<WebReportsPage> {
  late DateTime _from;
  late DateTime _to;

  /// Flujo de la analítica interactiva (donut de categorías). Es independiente
  /// de `ReportConfig.flow` (que sí admite "ambos") porque un único donut de
  /// reparto por categoría no tiene una lectura sensata mezclando ambos tipos.
  String _analyticsFlow = 'expense';

  String? _downloading;

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

  /// Persiste un cambio de configuración del informe (compartida con el
  /// móvil) y refresca los providers dependientes.
  Future<void> _patchConfig(ReportConfig c) async {
    final client = ref.read(webClientProvider);
    if (client == null) return;
    await client.putSettings({'reportConfig': c.encode()});
    bumpWebRefresh(ref);
  }

  Future<void> _download(String format, ReportConfig config) async {
    setState(() => _downloading = format);
    try {
      final map = <String, dynamic>{
        ...jsonDecode(config.encode()) as Map<String, dynamic>,
        'from': _from.toIso8601String(),
        'to': _to.toIso8601String(),
      };
      final Uint8List bytes =
          await ref.read(webClientProvider)!.report(format, map);
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
    final settings = ref.watch(webSettingsProvider).valueOrNull ?? SettingsDto();
    final config = ReportConfig.decode(settings.reportConfig);

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
      type: _analyticsFlow == 'income'
          ? TransactionType.income
          : TransactionType.expense,
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
                _analyticsFlow == 'income'
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
          _downloadCard(context, config),
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
            selected: {_analyticsFlow},
            onSelectionChanged: (s) => setState(() => _analyticsFlow = s.first),
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

  // --- Descarga: mismas opciones que ReportScreen (móvil), sobre el mismo
  // ReportConfig persistido en AppSettings.reportConfig. ---

  Widget _downloadCard(BuildContext context, ReportConfig config) {
    final anySection = config.dashboardPage ||
        config.balance ||
        config.evolution ||
        config.movements ||
        config.incomeByCategory ||
        config.expenseByAccount ||
        config.incomeByAccount ||
        config.accountUsage ||
        config.topConcepts ||
        config.comparison ||
        config.averages;

    return WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Generar informe',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
              'Lo genera tu móvil con las mismas opciones que la app '
              '(se recuerdan entre dispositivos).',
              style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          const SizedBox(height: 16),

          Text('Tipo de movimiento',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<ReportFlow>(
            segments: const [
              ButtonSegment(
                  value: ReportFlow.income,
                  label: Text('Ingresos'),
                  icon: Icon(Icons.south_west)),
              ButtonSegment(
                  value: ReportFlow.expense,
                  label: Text('Gastos'),
                  icon: Icon(Icons.north_east)),
              ButtonSegment(value: ReportFlow.both, label: Text('Ambos')),
            ],
            selected: {config.flow},
            onSelectionChanged: (s) =>
                _patchConfig(config.copyWith(flow: s.first)),
          ),
          const SizedBox(height: 16),

          Text('Secciones a incluir',
              style: Theme.of(context).textTheme.titleSmall),
          _sectionCheck(
              'Portada resumen (dashboard)',
              config.dashboardPage,
              (v) => _patchConfig(config.copyWith(dashboardPage: v))),
          if (config.dashboardPage)
            ReportCoverCardsEditor(
              cards: config.coverCards,
              onChanged: (v) => _patchConfig(config.copyWith(coverCards: v)),
            ),
          _sectionCheck('Balance', config.balance,
              (v) => _patchConfig(config.copyWith(balance: v))),
          _sectionCheck('Ingreso por categoría', config.incomeByCategory,
              (v) => _patchConfig(config.copyWith(incomeByCategory: v))),
          _sectionCheck('Gasto por cuenta', config.expenseByAccount,
              (v) => _patchConfig(config.copyWith(expenseByAccount: v))),
          _sectionCheck('Ingreso por cuenta', config.incomeByAccount,
              (v) => _patchConfig(config.copyWith(incomeByAccount: v))),
          _sectionCheck('Cuenta más usada', config.accountUsage,
              (v) => _patchConfig(config.copyWith(accountUsage: v))),
          _sectionCheck('Dónde más gastas', config.topConcepts,
              (v) => _patchConfig(config.copyWith(topConcepts: v))),
          _sectionCheck('Comparativa', config.comparison,
              (v) => _patchConfig(config.copyWith(comparison: v))),
          _sectionCheck('Medias y récords', config.averages,
              (v) => _patchConfig(config.copyWith(averages: v))),
          _sectionCheck('Evolución', config.evolution,
              (v) => _patchConfig(config.copyWith(evolution: v))),
          if (config.evolution)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: SegmentedButton<EvolutionGranularity>(
                segments: const [
                  ButtonSegment(
                      value: EvolutionGranularity.weekly,
                      label: Text('Semanal')),
                  ButtonSegment(
                      value: EvolutionGranularity.monthly,
                      label: Text('Mensual')),
                  ButtonSegment(
                      value: EvolutionGranularity.yearly,
                      label: Text('Anual')),
                ],
                selected: {config.granularity},
                onSelectionChanged: (s) =>
                    _patchConfig(config.copyWith(granularity: s.first)),
              ),
            ),
          _sectionCheck('Movimientos', config.movements,
              (v) => _patchConfig(config.copyWith(movements: v))),
          const SizedBox(height: 12),

          Text('Orden', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<AmountSort>(
                segments: const [
                  ButtonSegment(
                      value: AmountSort.desc,
                      label: Text('Mayor'),
                      icon: Icon(Icons.arrow_downward)),
                  ButtonSegment(
                      value: AmountSort.asc,
                      label: Text('Menor'),
                      icon: Icon(Icons.arrow_upward)),
                ],
                selected: {config.amountSort},
                onSelectionChanged: (s) =>
                    _patchConfig(config.copyWith(amountSort: s.first)),
              ),
              DropdownButton<MovementSort>(
                value: config.movementSort,
                onChanged: (v) => v == null
                    ? null
                    : _patchConfig(config.copyWith(movementSort: v)),
                items: [
                  for (final m in MovementSort.values)
                    DropdownMenuItem(value: m, child: Text(m.label)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          Text('Filtros', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.account_balance_wallet_outlined,
                    size: 18),
                label: Text(config.accountIds.isEmpty
                    ? 'Todas las cuentas'
                    : '${config.accountIds.length} cuentas'),
                onPressed: () => _pickAccounts(config),
              ),
              ActionChip(
                avatar: const Icon(Icons.category_outlined, size: 18),
                label: Text(config.categoryIds.isEmpty
                    ? 'Todas las categorías'
                    : '${config.categoryIds.length} categorías'),
                onPressed: () => _pickCategories(config),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Incluir cuentas archivadas'),
            value: config.includeArchived,
            onChanged: (v) =>
                _patchConfig(config.copyWith(includeArchived: v)),
          ),
          const SizedBox(height: 8),

          Text('Gráficos y detalle',
              style: Theme.of(context).textTheme.titleSmall),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Gráfico circular (categorías)'),
            value: config.pieChart,
            onChanged: (v) => _patchConfig(config.copyWith(pieChart: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Gráfico de barras (evolución)'),
            value: config.barChart,
            onChanged: (v) => _patchConfig(config.copyWith(barChart: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mostrar porcentajes'),
            value: config.showPercentages,
            onChanged: (v) =>
                _patchConfig(config.copyWith(showPercentages: v)),
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
                onPressed: (_downloading != null || !anySection)
                    ? null
                    : () => _download('pdf', config),
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
                onPressed: (_downloading != null || !anySection)
                    ? null
                    : () => _download('excel', config),
              ),
            ],
          ),
          if (!anySection)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Selecciona al menos una sección.'),
            ),
        ],
      ),
    );
  }

  Widget _sectionCheck(
          String title, bool value, ValueChanged<bool> onChanged) =>
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(title),
        value: value,
        onChanged: (v) => onChanged(v ?? false),
      );

  String _treeIndent(int depth) => depth == 0 ? '' : '${'    ' * depth}└ ';

  Future<void> _pickAccounts(ReportConfig config) async {
    final tree = ref.read(webAccountTreeProvider);
    final selected = {...config.accountIds};
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => AlertDialog(
          title: const Text('Filtrar por cuentas'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final r in tree)
                    CheckboxListTile(
                      dense: true,
                      title: Text('${_treeIndent(r.depth)}${r.item.name}'),
                      value: selected.contains(r.item.id),
                      onChanged: (v) => setSheet(() => v == true
                          ? selected.add(r.item.id)
                          : selected.remove(r.item.id)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            if (selected.isNotEmpty)
              TextButton(
                  onPressed: () => setSheet(() => selected.clear()),
                  child: const Text('Limpiar')),
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hecho')),
          ],
        ),
      ),
    );
    await _patchConfig(config.copyWith(accountIds: selected.toList()));
  }

  Future<void> _pickCategories(ReportConfig config) async {
    final expense = ref.read(webExpenseCategoryTreeProvider);
    final income = ref.read(webIncomeCategoryTreeProvider);
    final selected = {...config.categoryIds};
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => AlertDialog(
          title: const Text('Filtrar por categorías'),
          content: SizedBox(
            width: 360,
            height: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text('Gastos',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  for (final r in expense)
                    CheckboxListTile(
                      dense: true,
                      title: Text('${_treeIndent(r.depth)}${r.item.name}'),
                      value: selected.contains(r.item.id),
                      onChanged: (v) => setSheet(() => v == true
                          ? selected.add(r.item.id)
                          : selected.remove(r.item.id)),
                    ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text('Ingresos',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  for (final r in income)
                    CheckboxListTile(
                      dense: true,
                      title: Text('${_treeIndent(r.depth)}${r.item.name}'),
                      value: selected.contains(r.item.id),
                      onChanged: (v) => setSheet(() => v == true
                          ? selected.add(r.item.id)
                          : selected.remove(r.item.id)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            if (selected.isNotEmpty)
              TextButton(
                  onPressed: () => setSheet(() => selected.clear()),
                  child: const Text('Limpiar')),
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hecho')),
          ],
        ),
      ),
    );
    await _patchConfig(config.copyWith(categoryIds: selected.toList()));
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
