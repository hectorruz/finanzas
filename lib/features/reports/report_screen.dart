import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/report_excel.dart';
import '../../data/report_pdf.dart';
import '../../data/report_service.dart';

/// Pantalla para generar un informe descargable (PDF / Excel) de un tramo de
/// fechas, eligiendo qué secciones incluir.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  late DateTime _from;
  late DateTime _to;
  bool _movements = true;
  bool _balance = true;
  bool _evolution = true;
  EvolutionGranularity _granularity = EvolutionGranularity.monthly;
  ReportFlow _flow = ReportFlow.both;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month + 1, 0);
  }

  final _df = DateFormat('d MMM yyyy', 'es');

  bool get _anySection => _movements || _balance || _evolution;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Generar informe')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
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
                    ButtonSegment(
                      value: ReportFlow.both,
                      label: Text('Ambos'),
                    ),
                  ],
                  selected: {_flow},
                  onSelectionChanged: (s) => setState(() => _flow = s.first),
                ),
              ),
            ),
            const Divider(),
            const _SectionHeader('Incluir en el informe'),
            CheckboxListTile(
              title: const Text('Movimientos'),
              subtitle: const Text('Listado detallado del periodo'),
              value: _movements,
              onChanged: (v) => setState(() => _movements = v ?? false),
            ),
            CheckboxListTile(
              title: const Text('Balance'),
              subtitle: const Text('Resumen, saldo por cuenta y gasto por categoría'),
              value: _balance,
              onChanged: (v) => setState(() => _balance = v ?? false),
            ),
            CheckboxListTile(
              title: const Text('Evolución'),
              subtitle: const Text('Ingresos y gastos por periodo'),
              value: _evolution,
              onChanged: (v) => setState(() => _evolution = v ?? false),
            ),
            if (_evolution)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<EvolutionGranularity>(
                    segments: const [
                      ButtonSegment(
                        value: EvolutionGranularity.weekly,
                        label: Text('Semanal'),
                      ),
                      ButtonSegment(
                        value: EvolutionGranularity.monthly,
                        label: Text('Mensual'),
                      ),
                      ButtonSegment(
                        value: EvolutionGranularity.yearly,
                        label: Text('Anual'),
                      ),
                    ],
                    selected: {_granularity},
                    onSelectionChanged: (s) =>
                        setState(() => _granularity = s.first),
                  ),
                ),
              ),
            const Divider(),
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

  Widget _preset(String label, VoidCallback onTap) =>
      ActionChip(label: Text(label), onPressed: onTap);

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
      final options = ReportOptions(
        from: DateTime(_from.year, _from.month, _from.day),
        to: DateTime(_to.year, _to.month, _to.day, 23, 59, 59, 999),
        movements: _movements,
        balance: _balance,
        evolution: _evolution,
        granularity: _granularity,
        flow: _flow,
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
