import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/money/money.dart';
import 'models/enums.dart';
import 'report_service.dart';

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
  final doc = pw.Document();

  final sections = <pw.Widget>[];

  if (o.balance) {
    sections.add(_heading('Balance'));
    sections.add(_kvTable([
      ['Ingresos', _money(data.totalIncome)],
      ['Gastos', _money(data.totalExpense)],
      ['Neto', _signed(data.net)],
    ]));
    if (data.accountBalances.isNotEmpty) {
      sections.add(_subheading('Saldo por cuenta'));
      sections.add(pw.TableHelper.fromTextArray(
        headers: const ['Cuenta', 'Saldo actual'],
        data: [
          for (final a in data.accountBalances) [a.label, _money(a.cents)],
        ],
        cellAlignments: const {1: pw.Alignment.centerRight},
      ));
    }
    if (data.categoryExpenses.isNotEmpty) {
      sections.add(_subheading('Gasto por categoría'));
      sections.add(pw.TableHelper.fromTextArray(
        headers: const ['Categoría', 'Gasto'],
        data: [
          for (final c in data.categoryExpenses) [c.label, _money(c.cents)],
        ],
        cellAlignments: const {1: pw.Alignment.centerRight},
      ));
    }
    sections.add(pw.SizedBox(height: 16));
  }

  if (o.evolution) {
    sections.add(_heading('Evolución (${o.granularity.label.toLowerCase()})'));
    sections.add(pw.TableHelper.fromTextArray(
      headers: const ['Periodo', 'Ingresos', 'Gastos', 'Neto'],
      data: [
        for (final r in data.evolution)
          [r.label, _money(r.income), _money(r.expense), _signed(r.net)],
      ],
      cellAlignments: const {
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
      },
    ));
    sections.add(pw.SizedBox(height: 16));
  }

  if (o.movements) {
    sections.add(_heading('Movimientos (${data.movements.length})'));
    sections.add(pw.TableHelper.fromTextArray(
      headers: const ['Fecha', 'Tipo', 'Concepto', 'Categoría', 'Cuenta', 'Importe'],
      data: [
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
      cellAlignments: const {5: pw.Alignment.centerRight},
      cellStyle: const pw.TextStyle(fontSize: 9),
      headerStyle:
          pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
    ));
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (ctx) => ctx.pageNumber == 1
          ? pw.SizedBox()
          : pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text('Informe Finanzas',
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey)),
            ),
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Página ${ctx.pageNumber}/${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
      ),
      build: (ctx) => [
        pw.Header(
          level: 0,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Informe Finanzas',
                  style: pw.TextStyle(
                      fontSize: 22, fontWeight: pw.FontWeight.bold)),
              pw.Text('Del ${df.format(o.from)} al ${df.format(o.to)}',
                  style: const pw.TextStyle(
                      fontSize: 12, color: PdfColors.grey700)),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        ...sections,
      ],
    ),
  );

  final dir = await getTemporaryDirectory();
  final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
  final file = File('${dir.path}/finanzas_informe_$stamp.pdf');
  await file.writeAsBytes(await doc.save());
  return file;
}

pw.Widget _heading(String text) => pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6, top: 4),
      child: pw.Text(text,
          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
    );

pw.Widget _subheading(String text) => pw.Container(
      margin: const pw.EdgeInsets.only(top: 8, bottom: 4),
      child: pw.Text(text,
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
    );

pw.Widget _kvTable(List<List<String>> rows) => pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(1),
      },
      children: [
        for (final r in rows)
          pw.TableRow(children: [
            pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Text(r[0])),
            pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Text(r[1],
                    textAlign: pw.TextAlign.right)),
          ]),
      ],
    );
