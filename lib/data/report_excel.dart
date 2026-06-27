import 'dart:io';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'models/enums.dart';
import 'report_service.dart';

double _euros(int cents) => cents / 100.0;

String _typeLabel(TransactionType t) => switch (t) {
      TransactionType.income => 'Ingreso',
      TransactionType.expense => 'Gasto',
      TransactionType.transfer => 'Transferencia',
    };

/// Genera el .xlsx del informe (una hoja por sección) y lo escribe a temporal.
Future<File> buildReportExcel(ReportData data) async {
  final o = data.options;
  final df = DateFormat('yyyy-MM-dd', 'es');
  final excel = Excel.createExcel();
  final created = <String>[];

  Sheet sheetNamed(String name) {
    created.add(name);
    return excel[name];
  }

  if (o.balance) {
    final s = sheetNamed('Balance');
    s.appendRow([TextCellValue('Resumen del periodo')]);
    if (o.flow.showsIncome) {
      s.appendRow(
          [TextCellValue('Ingresos'), DoubleCellValue(_euros(data.totalIncome))]);
    }
    if (o.flow.showsExpense) {
      s.appendRow(
          [TextCellValue('Gastos'), DoubleCellValue(_euros(data.totalExpense))]);
    }
    if (o.flow == ReportFlow.both) {
      s.appendRow([TextCellValue('Neto'), DoubleCellValue(_euros(data.net))]);
    }
    if (data.accountBalances.isNotEmpty) {
      s.appendRow([]);
      s.appendRow([TextCellValue('Saldo por cuenta')]);
      s.appendRow([TextCellValue('Cuenta'), TextCellValue('Saldo actual')]);
      for (final a in data.accountBalances) {
        s.appendRow([TextCellValue(a.label), DoubleCellValue(_euros(a.cents))]);
      }
    }
    if (data.categoryExpenses.isNotEmpty) {
      s.appendRow([]);
      s.appendRow([TextCellValue('Gasto por categoría')]);
      s.appendRow([TextCellValue('Categoría'), TextCellValue('Gasto')]);
      for (final c in data.categoryExpenses) {
        s.appendRow([TextCellValue(c.label), DoubleCellValue(_euros(c.cents))]);
      }
    }
  }

  if (o.evolution) {
    final s = sheetNamed('Evolución');
    s.appendRow([
      TextCellValue('Periodo'),
      if (o.flow.showsIncome) TextCellValue('Ingresos'),
      if (o.flow.showsExpense) TextCellValue('Gastos'),
      if (o.flow == ReportFlow.both) TextCellValue('Neto'),
    ]);
    for (final r in data.evolution) {
      s.appendRow([
        TextCellValue(r.label),
        if (o.flow.showsIncome) DoubleCellValue(_euros(r.income)),
        if (o.flow.showsExpense) DoubleCellValue(_euros(r.expense)),
        if (o.flow == ReportFlow.both) DoubleCellValue(_euros(r.net)),
      ]);
    }
  }

  if (o.movements) {
    final s = sheetNamed('Movimientos');
    s.appendRow([
      TextCellValue('Fecha'),
      TextCellValue('Tipo'),
      TextCellValue('Concepto'),
      TextCellValue('Categoría'),
      TextCellValue('Cuenta'),
      TextCellValue('Importe'),
    ]);
    for (final t in data.movements) {
      s.appendRow([
        TextCellValue(df.format(t.date)),
        TextCellValue(_typeLabel(t.type)),
        TextCellValue(t.concept),
        TextCellValue(t.categoryId == null
            ? ''
            : (data.categoryNames[t.categoryId] ?? '')),
        TextCellValue(data.accountNames[t.accountId] ?? ''),
        DoubleCellValue(_euros(t.signedCents)),
      ]);
    }
  }

  // Eliminar la hoja por defecto si no es una de las nuestras.
  for (final name in excel.sheets.keys.toList()) {
    if (!created.contains(name)) excel.delete(name);
  }

  final dir = await getTemporaryDirectory();
  final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
  final file = File('${dir.path}/finanzas_informe_${o.flow.fileSlug}_$stamp.xlsx');
  final bytes = excel.encode();
  if (bytes != null) await file.writeAsBytes(bytes);
  return file;
}
