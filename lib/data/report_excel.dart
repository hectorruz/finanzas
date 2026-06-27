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

// Estilos. Se crean por celda (instancias frescas) para no compartir estado.
final _eur = NumFormat.custom(formatCode: r'#,##0.00 €');

CellStyle _moneyStyle() =>
    CellStyle(numberFormat: _eur, horizontalAlign: HorizontalAlign.Right);
CellStyle _titleStyle() => CellStyle(
      bold: true,
      fontSize: 13,
      fontColorHex: ExcelColor.fromHexString('FF1565C0'),
    );
CellStyle _headStyle() => CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('FFE3F2FD'),
    );

void _style(Sheet s, int row, int col, CellStyle style) {
  s.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).cellStyle =
      style;
}

/// Fila de título de sección (negrita, color).
void _titleRow(Sheet s, String text) {
  s.appendRow([TextCellValue(text)]);
  _style(s, s.maxRows - 1, 0, _titleStyle());
}

/// Fila de cabecera de tabla (negrita, fondo).
void _headerRow(Sheet s, List<CellValue?> cells) {
  s.appendRow(cells);
  final r = s.maxRows - 1;
  for (var c = 0; c < cells.length; c++) {
    _style(s, r, c, _headStyle());
  }
}

/// Fila de datos cuyas columnas a partir de la primera son importes en euros.
void _moneyRow(Sheet s, List<CellValue?> cells) {
  s.appendRow(cells);
  final r = s.maxRows - 1;
  for (var c = 1; c < cells.length; c++) {
    _style(s, r, c, _moneyStyle());
  }
}

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
    _titleRow(s, 'Resumen del periodo');
    if (o.flow.showsIncome) {
      _moneyRow(s, [
        TextCellValue('Ingresos'),
        DoubleCellValue(_euros(data.totalIncome)),
      ]);
    }
    if (o.flow.showsExpense) {
      _moneyRow(s, [
        TextCellValue('Gastos'),
        DoubleCellValue(_euros(data.totalExpense)),
      ]);
    }
    if (o.flow == ReportFlow.both) {
      _moneyRow(s,
          [TextCellValue('Neto'), DoubleCellValue(_euros(data.net))]);
    }
    if (data.accountBalances.isNotEmpty) {
      s.appendRow([]);
      _titleRow(s, 'Saldo por cuenta');
      _headerRow(s, [TextCellValue('Cuenta'), TextCellValue('Saldo actual')]);
      for (final a in data.accountBalances) {
        _moneyRow(s, [TextCellValue(a.label), DoubleCellValue(_euros(a.cents))]);
      }
    }
    if (data.categoryExpenses.isNotEmpty) {
      s.appendRow([]);
      _titleRow(s, 'Gasto por categoría');
      _headerRow(s, [TextCellValue('Categoría'), TextCellValue('Gasto')]);
      for (final c in data.categoryExpenses) {
        _moneyRow(s, [TextCellValue(c.label), DoubleCellValue(_euros(c.cents))]);
      }
    }
    s.setColumnWidth(0, 26);
    s.setColumnWidth(1, 16);
  }

  if (o.evolution) {
    final s = sheetNamed('Evolución');
    _headerRow(s, [
      TextCellValue('Periodo'),
      if (o.flow.showsIncome) TextCellValue('Ingresos'),
      if (o.flow.showsExpense) TextCellValue('Gastos'),
      if (o.flow == ReportFlow.both) TextCellValue('Neto'),
    ]);
    for (final r in data.evolution) {
      _moneyRow(s, [
        TextCellValue(r.label),
        if (o.flow.showsIncome) DoubleCellValue(_euros(r.income)),
        if (o.flow.showsExpense) DoubleCellValue(_euros(r.expense)),
        if (o.flow == ReportFlow.both) DoubleCellValue(_euros(r.net)),
      ]);
    }
    s.setColumnWidth(0, 22);
  }

  if (o.movements) {
    final s = sheetNamed('Movimientos');
    _headerRow(s, [
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
      _style(s, s.maxRows - 1, 5, _moneyStyle());
    }
    s.setColumnWidth(2, 28);
    s.setColumnWidth(3, 18);
    s.setColumnWidth(4, 18);
    s.setColumnWidth(5, 14);
  }

  // Eliminar la hoja por defecto si no es una de las nuestras.
  for (final name in excel.sheets.keys.toList()) {
    if (!created.contains(name)) excel.delete(name);
  }

  final dir = await getTemporaryDirectory();
  final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
  final file =
      File('${dir.path}/finanzas_informe_${o.flow.fileSlug}_$stamp.xlsx');
  final bytes = excel.encode();
  if (bytes != null) await file.writeAsBytes(bytes);
  return file;
}
