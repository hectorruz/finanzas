import 'dart:io';

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

String _money(int cents) => Money(cents).format();
String _signed(int cents) => Money(cents).formatSigned();

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
  final sections = <pw.Widget>[];

  if (o.balance) {
    sections.add(_sectionTitle('Balance'));
    sections.add(_summaryCards(data));
    if (data.accountBalances.isNotEmpty) {
      sections.add(_subheading('Saldo por cuenta'));
      sections.add(_table(
        headers: const ['Cuenta', 'Saldo actual'],
        rows: [
          for (final a in data.accountBalances) [a.label, _money(a.cents)],
        ],
        align: const {1: pw.Alignment.centerRight},
      ));
    }
    if (data.categoryExpenses.isNotEmpty) {
      sections.add(_subheading('Gasto por categoría'));
      sections.add(_table(
        headers: const ['Categoría', 'Gasto'],
        rows: [
          for (final c in data.categoryExpenses) [c.label, _money(c.cents)],
        ],
        align: const {1: pw.Alignment.centerRight},
      ));
    }
    sections.add(pw.SizedBox(height: 18));
  }

  if (o.evolution) {
    sections.add(_sectionTitle('Evolución · ${o.granularity.label.toLowerCase()}'));
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
      header: (ctx) => ctx.pageNumber == 1
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
      build: (ctx) => [
        _banner(o, df),
        pw.SizedBox(height: 18),
        ...sections,
      ],
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

pw.Widget _card(String label, String value, PdfColor color) => pw.Container(
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
        ],
      ),
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
