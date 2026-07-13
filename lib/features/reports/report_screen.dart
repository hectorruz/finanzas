import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/report_excel.dart';
import '../../data/report_pdf.dart';
import '../../data/report_service.dart';
import '../../data/models/category.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/settings_repository.dart';

/// Pantalla para generar un informe descargable (PDF / Excel) de un tramo de
/// fechas, eligiendo qué secciones incluir, cómo ordenarlas y qué filtrar.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  late DateTime _from;
  late DateTime _to;
  ReportConfig _config = const ReportConfig();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month + 1, 0);
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final settings = await ref.read(settingsRepositoryProvider).getOrCreate();
    if (!mounted) return;
    setState(() => _config = ReportConfig.decode(settings.reportConfig));
  }

  /// Actualiza la config en pantalla y la persiste (para recordarla).
  void _update(ReportConfig c) {
    setState(() => _config = c);
    ref
        .read(settingsRepositoryProvider)
        .update((s) => s.reportConfig = c.encode());
  }

  final _df = DateFormat('d MMM yyyy', 'es');

  bool get _anySection => _config.dashboardPage ||
      _config.balance ||
      _config.evolution ||
      _config.movements ||
      _config.incomeByCategory ||
      _config.expenseByAccount ||
      _config.incomeByAccount ||
      _config.accountUsage ||
      _config.topConcepts ||
      _config.comparison ||
      _config.averages;

  @override
  Widget build(BuildContext context) {
    final c = _config;
    return Scaffold(
      appBar: AppBar(title: const Text('Generar informe')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            // --- Periodo ---
            const _SectionHeader('Periodo'),
            ListTile(
              leading: const Icon(Icons.date_range),
              title: const Text('Rango de fechas'),
              subtitle: Text('${_df.format(_from)}  –  ${_df.format(_to)}'),
              onTap: _pickRange,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                children: [
                  _preset('Este mes', _thisMonth),
                  _preset('Mes pasado', _lastMonth),
                  _preset('Este año', _thisYear),
                  _preset('Últimos 12 meses', _last12Months),
                ],
              ),
            ),
            const Divider(),

            // --- Tipo de movimiento ---
            const _SectionHeader('Tipo de movimiento'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<ReportFlow>(
                  segments: const [
                    ButtonSegment(
                      value: ReportFlow.income,
                      label: Text('Ingresos'),
                      icon: Icon(Icons.south_west),
                    ),
                    ButtonSegment(
                      value: ReportFlow.expense,
                      label: Text('Gastos'),
                      icon: Icon(Icons.north_east),
                    ),
                    ButtonSegment(value: ReportFlow.both, label: Text('Ambos')),
                  ],
                  selected: {c.flow},
                  onSelectionChanged: (s) =>
                      _update(c.copyWith(flow: s.first)),
                ),
              ),
            ),
            const Divider(),

            // --- Secciones ---
            const _SectionHeader('Secciones a incluir'),
            _sectionTile('Portada resumen (dashboard)',
                'KPIs destacados y gráfico', c.dashboardPage,
                (v) => _update(c.copyWith(dashboardPage: v))),
            _sectionTile('Balance', 'Resumen, saldo por cuenta y gasto por categoría',
                c.balance, (v) => _update(c.copyWith(balance: v))),
            _sectionTile('Ingreso por categoría', 'De dónde vienen tus ingresos',
                c.incomeByCategory, (v) => _update(c.copyWith(incomeByCategory: v))),
            _sectionTile('Gasto por cuenta', 'Cuánto gastas desde cada cuenta',
                c.expenseByAccount, (v) => _update(c.copyWith(expenseByAccount: v))),
            _sectionTile('Ingreso por cuenta', 'Cuánto ingresas en cada cuenta',
                c.incomeByAccount, (v) => _update(c.copyWith(incomeByAccount: v))),
            _sectionTile('Cuenta más usada', 'Nº de movimientos y volumen por cuenta',
                c.accountUsage, (v) => _update(c.copyWith(accountUsage: v))),
            _sectionTile('Dónde más gastas', 'Ranking de conceptos con más gasto',
                c.topConcepts, (v) => _update(c.copyWith(topConcepts: v))),
            _sectionTile('Comparativa', 'Variación frente al periodo anterior',
                c.comparison, (v) => _update(c.copyWith(comparison: v))),
            _sectionTile('Medias y récords', 'Gasto medio, mayor gasto e ingreso',
                c.averages, (v) => _update(c.copyWith(averages: v))),
            _sectionTile('Evolución', 'Ingresos y gastos por periodo',
                c.evolution, (v) => _update(c.copyWith(evolution: v))),
            _sectionTile('Movimientos', 'Listado detallado del periodo',
                c.movements, (v) => _update(c.copyWith(movements: v))),

            if (c.evolution)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
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
                    selected: {c.granularity},
                    onSelectionChanged: (s) =>
                        _update(c.copyWith(granularity: s.first)),
                  ),
                ),
              ),
            const Divider(),

            // --- Orden ---
            const _SectionHeader('Orden'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  const Expanded(child: Text('Importes')),
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
                    selected: {c.amountSort},
                    onSelectionChanged: (s) =>
                        _update(c.copyWith(amountSort: s.first)),
                  ),
                ],
              ),
            ),
            ListTile(
              title: const Text('Orden de movimientos'),
              trailing: DropdownButton<MovementSort>(
                value: c.movementSort,
                onChanged: (v) =>
                    v == null ? null : _update(c.copyWith(movementSort: v)),
                items: [
                  for (final m in MovementSort.values)
                    DropdownMenuItem(value: m, child: Text(m.label)),
                ],
              ),
            ),
            const Divider(),

            // --- Filtros ---
            const _SectionHeader('Filtros'),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Cuentas'),
              subtitle: Text(c.accountIds.isEmpty
                  ? 'Todas'
                  : '${c.accountIds.length} seleccionadas'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickAccounts,
            ),
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('Categorías'),
              subtitle: Text(c.categoryIds.isEmpty
                  ? 'Todas'
                  : '${c.categoryIds.length} seleccionadas'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickCategories,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.archive_outlined),
              title: const Text('Incluir cuentas archivadas'),
              value: c.includeArchived,
              onChanged: (v) => _update(c.copyWith(includeArchived: v)),
            ),
            const Divider(),

            // --- Gráficos y detalle (PDF) ---
            const _SectionHeader('Gráficos y detalle'),
            SwitchListTile(
              title: const Text('Gráfico circular (categorías)'),
              value: c.pieChart,
              onChanged: (v) => _update(c.copyWith(pieChart: v)),
            ),
            SwitchListTile(
              title: const Text('Gráfico de barras (evolución)'),
              value: c.barChart,
              onChanged: (v) => _update(c.copyWith(barChart: v)),
            ),
            SwitchListTile(
              title: const Text('Mostrar porcentajes'),
              subtitle: const Text('Columna de % del total en las tablas'),
              value: c.showPercentages,
              onChanged: (v) => _update(c.copyWith(showPercentages: v)),
            ),
            const Divider(),

            // --- Botones ---
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  FilledButton.icon(
                    onPressed: _anySection ? () => _generate(_Format.pdf) : null,
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Descargar PDF'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed:
                        _anySection ? () => _generate(_Format.excel) : null,
                    icon: const Icon(Icons.table_chart),
                    label: const Text('Descargar Excel'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                  if (!_anySection)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text('Selecciona al menos una sección.'),
                    ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: CircularProgressIndicator(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTile(String title, String subtitle, bool value,
          ValueChanged<bool> onChanged) =>
      CheckboxListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        value: value,
        onChanged: (v) => onChanged(v ?? false),
      );

  Widget _preset(String label, VoidCallback onTap) =>
      ActionChip(label: Text(label), onPressed: onTap);

  Future<void> _pickAccounts() async {
    final accounts = ref.read(accountsProvider).valueOrNull ?? const [];
    final selected = {..._config.accountIds};
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => ListView(
          shrinkWrap: true,
          padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(ctx).bottom),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('Filtrar por cuentas',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final a in accounts)
              CheckboxListTile(
                title: Text(a.name),
                value: selected.contains(a.id),
                onChanged: (v) => setSheet(() =>
                    v == true ? selected.add(a.id) : selected.remove(a.id)),
              ),
          ],
        ),
      ),
    );
    _update(_config.copyWith(accountIds: selected.toList()));
  }

  Future<void> _pickCategories() async {
    final categories = ref.read(categoriesProvider).valueOrNull ?? const [];
    final byId = {for (final c in categories) c.id: c};
    final selected = {..._config.categoryIds};
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => ListView(
          shrinkWrap: true,
          padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(ctx).bottom),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('Filtrar por categorías',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final cat in categories)
              CheckboxListTile(
                title: Text(categoryFullName(cat.id, byId, fallback: cat.name)),
                value: selected.contains(cat.id),
                onChanged: (v) => setSheet(() =>
                    v == true ? selected.add(cat.id) : selected.remove(cat.id)),
              ),
          ],
        ),
      ),
    );
    _update(_config.copyWith(categoryIds: selected.toList()));
  }

  void _thisMonth() {
    final n = DateTime.now();
    setState(() {
      _from = DateTime(n.year, n.month, 1);
      _to = DateTime(n.year, n.month + 1, 0);
    });
  }

  void _lastMonth() {
    final n = DateTime.now();
    setState(() {
      _from = DateTime(n.year, n.month - 1, 1);
      _to = DateTime(n.year, n.month, 0);
    });
  }

  void _thisYear() {
    final n = DateTime.now();
    setState(() {
      _from = DateTime(n.year, 1, 1);
      _to = DateTime(n.year, 12, 31);
    });
  }

  void _last12Months() {
    final n = DateTime.now();
    setState(() {
      _from = DateTime(n.year, n.month - 11, 1);
      _to = DateTime(n.year, n.month + 1, 0);
    });
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      locale: const Locale('es', 'ES'),
    );
    if (picked != null) {
      setState(() {
        _from = picked.start;
        _to = picked.end;
      });
    }
  }

  Future<void> _generate(_Format format) async {
    setState(() => _busy = true);
    try {
      final options = _config.toOptions(
        from: DateTime(_from.year, _from.month, _from.day),
        to: DateTime(_to.year, _to.month, _to.day, 23, 59, 59, 999),
      );
      final data = await ref.read(reportServiceProvider).build(options);
      final file = switch (format) {
        _Format.pdf => await buildReportPdf(data),
        _Format.excel => await buildReportExcel(data),
      };
      await Share.shareXFiles([XFile(file.path)], subject: 'Informe Finanzas');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al generar el informe: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

enum _Format { pdf, excel }

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
