import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/money/money.dart';
import 'models/enums.dart';
import 'report_service.dart';

// Paleta del informe.
const _accent = PdfColor.fromInt(0xFF1E88E5);
const _accentDark = PdfColor.fromInt(0xFF1565C0);
const _income = PdfColor.fromInt(0xFF2E7D32);
const _expense = PdfColor.fromInt(0xFFC62828);
const _zebra = PdfColor.fromInt(0xFFF2F6FB);
const _ink = PdfColor.fromInt(0xFF263238);

/// Paleta para sectores de la tarta y series de gráficos.
const _palette = <PdfColor>[
  PdfColor.fromInt(0xFF1E88E5),
  PdfColor.fromInt(0xFFE53935),
  PdfColor.fromInt(0xFF43A047),
  PdfColor.fromInt(0xFFFB8C00),
  PdfColor.fromInt(0xFF8E24AA),
  PdfColor.fromInt(0xFF00ACC1),
  PdfColor.fromInt(0xFFFDD835),
  PdfColor.fromInt(0xFF6D4C41),
  PdfColor.fromInt(0xFF3949AB),
  PdfColor.fromInt(0xFFC0CA33),
];

String _money(int cents) => Money(cents).format();
String _signed(int cents) => Money(cents).formatSigned();

String _pct(int part, int whole) =>
    whole <= 0 ? '—' : '${(part / whole * 100).toStringAsFixed(1)} %';

String _typeLabel(TransactionType t) => switch (t) {
      TransactionType.income => 'Ingreso',
      TransactionType.expense => 'Gasto',
      TransactionType.transfer => 'Transfer.',
    };

/// Genera el PDF del informe y lo escribe a un fichero temporal.
Future<File> buildReportPdf(ReportData data) async {
  final o = data.options;
  final df = DateFormat('d MMM yyyy', 'es');

  // Fuente con soporte Unicode (incluye el símbolo €, que las fuentes
  // estándar del PDF no traen).
  final base = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
  final bold =
      pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
  final theme = pw.ThemeData.withFont(base: base, bold: bold);

  final doc = pw.Document();

  // Tarta de reparto de gasto por categoría.
  final pie = (o.pieChart && data.categoryExpenses.isNotEmpty)
      ? _pieBlock(data.categoryExpenses, data.totalExpense)
      : null;

  // --- Página dashboard (portada personalizable) ---
  if (o.dashboardPage) {
    final content = buildCoverWidgets(data, pie, df);
    doc.addPage(
      pw.Page(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 32),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: content,
        ),
      ),
    );
  }

  // --- Secciones de detalle (MultiPage) ---
  final sections = <pw.Widget>[];

  if (!o.dashboardPage) {
    sections.add(_banner(o, df));
    sections.add(pw.SizedBox(height: 18));
  }

  if (o.balance) {
    sections.add(_sectionTitle('Balance'));
    sections.add(_summaryCards(data));
    if (o.comparison && data.comparison != null) {
      sections.add(pw.SizedBox(height: 6));
      sections.add(_comparisonRow(data));
    }
    if (data.accountBalances.isNotEmpty) {
      sections.add(_subheading('Saldo por cuenta'));
      sections.add(_amountTable('Cuenta', data.accountBalances, null,
          showPct: false));
    }
    if (data.categoryExpenses.isNotEmpty) {
      sections.add(_subheading('Gasto por categoría'));
      sections.add(_amountTable(
          'Categoría', data.categoryExpenses, data.totalExpense,
          showPct: o.showPercentages));
    }
    // Si no hay portada, la tarta va aquí.
    if (!o.dashboardPage && pie != null) {
      sections.add(pw.SizedBox(height: 8));
      sections.add(pie);
    }
    sections.add(pw.SizedBox(height: 18));
  }

  if (o.incomeByCategory && data.categoryIncomes.isNotEmpty) {
    sections.add(_sectionTitle('Ingreso por categoría'));
    sections.add(_amountTable(
        'Categoría', data.categoryIncomes, data.totalIncome,
        showPct: o.showPercentages));
    sections.add(pw.SizedBox(height: 18));
  }

  if (o.expenseByAccount && data.expenseByAccount.isNotEmpty) {
    sections.add(_sectionTitle('Gasto por cuenta'));
    sections.add(_amountTable(
        'Cuenta', data.expenseByAccount, data.totalExpense,
        showPct: o.showPercentages));
    sections.add(pw.SizedBox(height: 18));
  }

  if (o.incomeByAccount && data.incomeByAccount.isNotEmpty) {
    sections.add(_sectionTitle('Ingreso por cuenta'));
    sections.add(_amountTable(
        'Cuenta', data.incomeByAccount, data.totalIncome,
        showPct: o.showPercentages));
    sections.add(pw.SizedBox(height: 18));
  }

  if (o.accountUsage && data.accountUsage.isNotEmpty) {
    sections.add(_sectionTitle('Cuenta más usada'));
    sections.add(_table(
      headers: const ['Cuenta', 'Nº mov.', 'Volumen'],
      rows: [
        for (final u in data.accountUsage)
          [u.label, '${u.count}', _money(u.volumeCents)],
      ],
      align: const {
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
      },
    ));
    sections.add(pw.SizedBox(height: 18));
  }

  if (o.topConcepts && data.topConcepts.isNotEmpty) {
    sections.add(_sectionTitle('Dónde más gastas'));
    sections.add(_amountTable('Concepto', data.topConcepts, data.totalExpense,
        showPct: o.showPercentages));
    sections.add(pw.SizedBox(height: 18));
  }

  if (o.evolution && data.evolution.isNotEmpty) {
    sections.add(
        _sectionTitle('Evolución · ${o.granularity.label.toLowerCase()}'));
    if (o.barChart) {
      sections.add(_barBlock(data));
      sections.add(pw.SizedBox(height: 8));
    }
    sections.add(_table(
      headers: [
        'Periodo',
        if (o.flow.showsIncome) 'Ingresos',
        if (o.flow.showsExpense) 'Gastos',
        if (o.flow == ReportFlow.both) 'Neto',
      ],
      rows: [
        for (final r in data.evolution)
          [
            r.label,
            if (o.flow.showsIncome) _money(r.income),
            if (o.flow.showsExpense) _money(r.expense),
            if (o.flow == ReportFlow.both) _signed(r.net),
          ],
      ],
      align: const {
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
      },
    ));
    sections.add(pw.SizedBox(height: 18));
  }

  if (o.averages && data.averages != null) {
    sections.add(_sectionTitle('Medias y récords'));
    sections.add(_averagesBlock(data));
    sections.add(pw.SizedBox(height: 18));
  }

  if (o.movements) {
    sections.add(_sectionTitle('Movimientos · ${data.movements.length}'));
    sections.add(_table(
      headers: const [
        'Fecha',
        'Tipo',
        'Concepto',
        'Categoría',
        'Cuenta',
        'Importe'
      ],
      rows: [
        for (final t in data.movements)
          [
            df.format(t.date),
            _typeLabel(t.type),
            t.concept,
            t.categoryId == null
                ? ''
                : (data.categoryNames[t.categoryId] ?? ''),
            data.accountNames[t.accountId] ?? '',
            _signed(t.signedCents),
          ],
      ],
      align: const {5: pw.Alignment.centerRight},
      fontSize: 9,
    ));
  }

  doc.addPage(
    pw.MultiPage(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 32),
      header: (ctx) => (ctx.pageNumber == 1 && !o.dashboardPage)
          ? pw.SizedBox()
          : pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(bottom: 10),
              child: pw.Text('Informe Finanzas',
                  style:
                      const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
            ),
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
      ),
      build: (ctx) => sections,
    ),
  );

  final dir = await getTemporaryDirectory();
  final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
  final file =
      File('${dir.path}/finanzas_informe_${o.flow.fileSlug}_$stamp.pdf');
  await file.writeAsBytes(await doc.save());
  return file;
}

/// Cabecera con banda de color: título, rango de fechas y tipo de flujo.
pw.Widget _banner(ReportOptions o, DateFormat df) => pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: const pw.BoxDecoration(
        color: _accent,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Informe Finanzas',
              style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white)),
          pw.SizedBox(height: 4),
          pw.Text('Del ${df.format(o.from)} al ${df.format(o.to)}',
              style: const pw.TextStyle(
                  fontSize: 12, color: PdfColor.fromInt(0xFFE3F2FD))),
          pw.SizedBox(height: 2),
          pw.Text('Movimientos: ${o.flow.label.toLowerCase()}',
              style: const pw.TextStyle(
                  fontSize: 10, color: PdfColor.fromInt(0xFFE3F2FD))),
        ],
      ),
    );

/// Tarjetas de resumen (ingresos / gastos / neto) según el flujo.
pw.Widget _summaryCards(ReportData data) {
  final o = data.options;
  final cards = <pw.Widget>[
    if (o.flow.showsIncome) _card('Ingresos', _money(data.totalIncome), _income),
    if (o.flow.showsExpense) _card('Gastos', _money(data.totalExpense), _expense),
    if (o.flow == ReportFlow.both)
      _card('Neto', _signed(data.net), data.net >= 0 ? _income : _expense),
  ];
  return _cardRow(cards);
}

pw.Widget _cardRow(List<pw.Widget> cards) {
  final children = <pw.Widget>[];
  for (var i = 0; i < cards.length; i++) {
    children.add(pw.Expanded(child: cards[i]));
    if (i != cards.length - 1) children.add(pw.SizedBox(width: 12));
  }
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Row(children: children),
  );
}

/// Widgets de la portada dashboard (banner + rejilla de KPIs + bloques), en el
/// orden en que se apilan en la página. Expuesto (con [df] inyectable) para el
/// test de regresión que comprueba que **de verdad se pintan dentro de la
/// página**: la portada estuvo saliendo con solo el banner porque la rejilla
/// usaba `CrossAxisAlignment.stretch` dentro de una `Column` (altura sin
/// acotar → constraints infinitas → todo lo posterior desaparecía en
/// silencio), y ningún test de "el PDF no está vacío" lo detectaba.
@visibleForTesting
List<pw.Widget> buildCoverWidgets(
    ReportData data, pw.Widget? pie, DateFormat df) {
  // resolveCoverCards (no effectiveCoverCards) para que la portada no salga
  // con solo el encabezado cuando las tarjetas elegidas no aplican al flujo o
  // no hay datos: en ese caso recae en las de por defecto.
  final cards = resolveCoverCards(data);
  final kpiTiles = [
    for (final key in cards)
      if (_kpiCoverKeys.contains(key))
        if (_kpiTileFor(key, data) case final w?) w,
  ];
  final blocks = [
    for (final key in cards)
      if (!_kpiCoverKeys.contains(key))
        if (_blockFor(key, data, pie) case final w?) w,
  ];
  return [
    _banner(data.options, df),
    pw.SizedBox(height: 18),
    if (kpiTiles.isNotEmpty) _kpiGridFrom(kpiTiles),
    for (final b in blocks) ...[pw.SizedBox(height: 20), b],
  ];
}

/// Claves de tarjeta de portada que van en la rejilla de KPIs (el resto son
/// gráficos/bloques de análisis a ancho completo, vía [_blockFor]).
const _kpiCoverKeys = {
  'kpiIncome',
  'kpiExpense',
  'kpiNet',
  'kpiSavingsRate',
  'kpiBiggestExpense',
  'kpiTopCategory',
  'kpiTopAccount',
};

/// Construye la tarjeta KPI de portada para una clave, o `null` si el flujo o
/// los datos disponibles no la hacen aplicable (p. ej. "Neto" con flujo de
/// solo gastos).
pw.Widget? _kpiTileFor(String key, ReportData data) {
  final o = data.options;
  switch (key) {
    case 'kpiIncome':
      return o.flow.showsIncome
          ? _card('Ingresos', _money(data.totalIncome), _income)
          : null;
    case 'kpiExpense':
      return o.flow.showsExpense
          ? _card('Gastos', _money(data.totalExpense), _expense)
          : null;
    case 'kpiNet':
      return o.flow == ReportFlow.both
          ? _card('Neto', _signed(data.net), data.net >= 0 ? _income : _expense)
          : null;
    case 'kpiSavingsRate':
      return o.flow == ReportFlow.both
          ? _card('Ahorro', '${data.savingsRate.toStringAsFixed(1)} %',
              data.savingsRate >= 0 ? _income : _expense)
          : null;
    case 'kpiBiggestExpense':
      final m = data.maxExpense;
      return m == null
          ? null
          : _card('Mayor gasto', _money(m.cents), _expense,
              sub: m.concept.isEmpty ? null : m.concept);
    case 'kpiTopCategory':
      if (data.categoryExpenses.isEmpty) return null;
      final top = o.amountSort == AmountSort.desc
          ? data.categoryExpenses.first
          : data.categoryExpenses.last;
      return _card('Categoría top', _money(top.cents), _accentDark,
          sub: top.label);
    case 'kpiTopAccount':
      if (data.accountUsage.isEmpty) return null;
      final top = data.accountUsage.first;
      return _card('Cuenta más usada', '${top.count} mov.', _accentDark,
          sub: top.label);
    default:
      return null;
  }
}

/// Construye el bloque de portada (gráfico o análisis) para una clave, o
/// `null` si no aplica (gráfico desactivado, sin datos, o sección no pedida).
pw.Widget? _blockFor(String key, ReportData data, pw.Widget? pie) {
  final o = data.options;
  switch (key) {
    case 'chartCategoryPie':
      return pie == null
          ? null
          : pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              _sectionTitle('Reparto de gasto'),
              pie,
            ]);
    case 'chartEvolutionBar':
      return (o.barChart && data.evolution.isNotEmpty)
          ? pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              _sectionTitle('Evolución'),
              _barBlock(data),
            ])
          : null;
    case 'blockComparison':
      return data.comparison == null ? null : _comparisonRow(data);
    case 'blockAverages':
      return data.averages == null
          ? null
          : pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              _sectionTitle('Medias y récords'),
              _averagesBlock(data),
            ]);
    case 'blockTopCategories':
      return data.categoryExpenses.isEmpty
          ? null
          : pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              _sectionTitle('Top categorías de gasto'),
              _amountTable('Categoría', data.categoryExpenses.take(5).toList(),
                  data.totalExpense,
                  showPct: o.showPercentages),
            ]);
    default:
      return null;
  }
}

/// Rejilla de KPIs (3 por fila) para la portada dashboard.
pw.Widget _kpiGridFrom(List<pw.Widget> tiles) {
  // Disponer en filas de 3.
  final rows = <pw.Widget>[];
  for (var i = 0; i < tiles.length; i += 3) {
    final chunk = tiles.sublist(i, (i + 3).clamp(0, tiles.length));
    // Rellenar con huecos para mantener el ancho.
    final cells = <pw.Widget>[];
    for (var j = 0; j < 3; j++) {
      if (j < chunk.length) {
        cells.add(pw.Expanded(child: chunk[j]));
      } else {
        cells.add(pw.Expanded(child: pw.SizedBox()));
      }
      if (j != 2) cells.add(pw.SizedBox(width: 12));
    }
    // ⚠️ Nunca `CrossAxisAlignment.stretch` aquí: esta fila vive dentro de la
    // `Column` de la portada, cuyos hijos se miden con altura sin acotar; con
    // stretch, package:pdf impone a las celdas minHeight = maxHeight = ∞ y la
    // rejilla (y todo lo que viene detrás) deja de pintarse sin ningún error.
    rows.add(pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start, children: cells),
    ));
  }
  return pw.Column(children: rows);
}

pw.Widget _card(String label, String value, PdfColor color, {String? sub}) =>
    pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label.toUpperCase(),
              style: const pw.TextStyle(
                  fontSize: 9, color: PdfColors.grey600, letterSpacing: 0.5)),
          pw.SizedBox(height: 6),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 15, fontWeight: pw.FontWeight.bold, color: color)),
          if (sub != null) ...[
            pw.SizedBox(height: 3),
            pw.Text(sub,
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
                style:
                    const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          ],
        ],
      ),
    );

/// Fila comparativa con el periodo anterior.
pw.Widget _comparisonRow(ReportData data) {
  final o = data.options;
  final c = data.comparison!;
  String variation(int now, int prev) {
    if (prev == 0) return now == 0 ? '—' : 'nuevo';
    final v = (now - prev) / prev * 100;
    final sign = v >= 0 ? '+' : '';
    return '$sign${v.toStringAsFixed(1)} %';
  }

  final rows = <List<String>>[];
  if (o.flow.showsIncome) {
    rows.add([
      'Ingresos',
      _money(data.totalIncome),
      _money(c.income),
      variation(data.totalIncome, c.income)
    ]);
  }
  if (o.flow.showsExpense) {
    rows.add([
      'Gastos',
      _money(data.totalExpense),
      _money(c.expense),
      variation(data.totalExpense, c.expense)
    ]);
  }
  if (o.flow == ReportFlow.both) {
    rows.add([
      'Neto',
      _signed(data.net),
      _signed(c.net),
      variation(data.net, c.net)
    ]);
  }
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _subheading('Comparativa con el periodo anterior'),
      _table(
        headers: const ['', 'Actual', 'Anterior', 'Variación'],
        rows: rows,
        align: const {
          1: pw.Alignment.centerRight,
          2: pw.Alignment.centerRight,
          3: pw.Alignment.centerRight,
        },
      ),
    ],
  );
}

/// Bloque de medias y récords.
pw.Widget _averagesBlock(ReportData data) {
  final a = data.averages!;
  final o = data.options;
  final rows = <List<String>>[];
  if (o.flow.showsExpense) {
    rows.add(['Gasto medio diario', _money(a.avgDailyExpense)]);
    rows.add(['Gasto medio mensual', _money(a.avgMonthlyExpense)]);
  }
  if (o.flow.showsIncome) {
    rows.add(['Ingreso medio diario', _money(a.avgDailyIncome)]);
  }
  if (a.maxExpense != null) {
    rows.add([
      'Mayor gasto',
      '${_money(a.maxExpense!.cents)}'
          '${a.maxExpense!.concept.isEmpty ? '' : ' · ${a.maxExpense!.concept}'}'
    ]);
  }
  if (a.maxIncome != null) {
    rows.add([
      'Mayor ingreso',
      '${_money(a.maxIncome!.cents)}'
          '${a.maxIncome!.concept.isEmpty ? '' : ' · ${a.maxIncome!.concept}'}'
    ]);
  }
  return _table(
    headers: const ['Métrica', 'Valor'],
    rows: rows,
    align: const {1: pw.Alignment.centerRight},
  );
}

/// Tarta con leyenda lateral (color + etiqueta + importe + %).
pw.Widget _pieBlock(List<LabeledAmount> items, int total) {
  // Top 8 + "Otros".
  final ordered = [...items]..sort((a, b) => b.cents.compareTo(a.cents));
  final slices = <LabeledAmount>[];
  if (ordered.length > 8) {
    slices.addAll(ordered.take(7));
    final rest = ordered.skip(7).fold<int>(0, (s, e) => s + e.cents);
    slices.add((label: 'Otros', cents: rest));
  } else {
    slices.addAll(ordered);
  }

  final legend = <pw.Widget>[];
  for (var i = 0; i < slices.length; i++) {
    final s = slices[i];
    legend.add(pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(children: [
        pw.Container(
            width: 9,
            height: 9,
            color: _palette[i % _palette.length]),
        pw.SizedBox(width: 6),
        pw.Expanded(
            child: pw.Text(s.label,
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
                style: const pw.TextStyle(fontSize: 9, color: _ink))),
        pw.SizedBox(width: 6),
        pw.Text('${_money(s.cents)}  ·  ${_pct(s.cents, total)}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      ]),
    ));
  }

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(
        width: 150,
        height: 150,
        child: pw.Chart(
          grid: pw.PieGrid(),
          datasets: [
            for (var i = 0; i < slices.length; i++)
              pw.PieDataSet(
                legend: '',
                value: slices[i].cents.toDouble(),
                color: _palette[i % _palette.length],
              ),
          ],
        ),
      ),
      pw.SizedBox(width: 16),
      pw.Expanded(
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: legend)),
    ],
  );
}

/// Gráfico de barras de la evolución (ingresos vs gastos por periodo).
pw.Widget _barBlock(ReportData data) {
  final o = data.options;
  final rows = data.evolution;
  // Limitar a los últimos 12 periodos para que las barras se lean.
  final shown = rows.length > 12 ? rows.sublist(rows.length - 12) : rows;

  // Se trabaja en euros para que el eje Y muestre cifras legibles.
  double eur(int c) => c / 100.0;
  var maxV = 0.0;
  for (final r in shown) {
    if (o.flow.showsIncome && eur(r.income) > maxV) maxV = eur(r.income);
    if (o.flow.showsExpense && eur(r.expense) > maxV) maxV = eur(r.expense);
  }
  if (maxV <= 0) maxV = 1;
  final top = maxV.ceilToDouble();

  // Con un solo periodo, el eje X de `FixedAxis` queda con rango 0..0 y su
  // interpolación divide por cero: en debug salta la aserción `!value.isNaN`
  // de `PdfNum` y en release (sin aserciones) el NaN se escribe en el flujo
  // de contenido del PDF, dejando la página en blanco en el visor. Se centra
  // el único periodo entre dos etiquetas vacías para dar anchura al eje.
  final single = shown.length == 1;
  final labels = [
    if (single) '',
    for (final r in shown) _shortLabel(r.label),
    if (single) '',
  ];
  final dx = single ? 1.0 : 0.0;
  final incomePts = [
    for (var i = 0; i < shown.length; i++)
      pw.PointChartValue(i + dx, eur(shown[i].income))
  ];
  final expensePts = [
    for (var i = 0; i < shown.length; i++)
      pw.PointChartValue(i + dx, eur(shown[i].expense))
  ];

  final datasets = <pw.Dataset>[
    if (o.flow.showsIncome)
      pw.BarDataSet(
          data: incomePts,
          color: _income,
          width: 7,
          offset: o.flow == ReportFlow.both ? -4.5 : 0),
    if (o.flow.showsExpense)
      pw.BarDataSet(
          data: expensePts,
          color: _expense,
          width: 7,
          offset: o.flow == ReportFlow.both ? 4.5 : 0),
  ];

  return pw.SizedBox(
    height: 150,
    child: pw.Chart(
      grid: pw.CartesianGrid(
        xAxis: pw.FixedAxis.fromStrings(labels),
        yAxis: pw.FixedAxis([0, top / 2, top]),
      ),
      datasets: datasets,
    ),
  );
}

String _shortLabel(String label) {
  // "septiembre 2025" -> "sep 25"; "Sem. 1 sep 2025" -> "1 sep"; deja años tal cual.
  final parts = label.replaceFirst('Sem. ', '').split(' ');
  if (parts.length >= 2) {
    final m = parts[parts.length - 2];
    return m.length > 3 ? '${m.substring(0, 3)}.' : m;
  }
  return label;
}

/// Tabla de importes etiquetados, con columna opcional de %.
pw.Widget _amountTable(
  String header,
  List<LabeledAmount> items,
  int? total, {
  required bool showPct,
}) =>
    _table(
      headers: [header, 'Importe', if (showPct) '%'],
      rows: [
        for (final e in items)
          [
            e.label,
            _money(e.cents),
            if (showPct) _pct(e.cents, total ?? 0),
          ],
      ],
      align: {
        1: pw.Alignment.centerRight,
        if (showPct) 2: pw.Alignment.centerRight,
      },
    );

pw.Widget _sectionTitle(String text) => pw.Container(
      margin: const pw.EdgeInsets.only(top: 4, bottom: 10),
      padding: const pw.EdgeInsets.only(bottom: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _accent, width: 1.5)),
      ),
      child: pw.Text(text,
          style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: _accentDark)),
    );

pw.Widget _subheading(String text) => pw.Container(
      margin: const pw.EdgeInsets.only(top: 6, bottom: 6),
      child: pw.Text(text,
          style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: _ink)),
    );

pw.Widget _table({
  required List<String> headers,
  required List<List<String>> rows,
  Map<int, pw.Alignment>? align,
  double fontSize = 10,
}) =>
    pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      border: null,
      headerHeight: 24,
      cellHeight: 20,
      headerStyle: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: _accent),
      cellStyle: pw.TextStyle(fontSize: fontSize, color: _ink),
      oddRowDecoration: const pw.BoxDecoration(color: _zebra),
      headerAlignment: pw.Alignment.centerLeft,
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: align,
      cellPadding:
          const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    );
