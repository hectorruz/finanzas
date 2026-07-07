import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart';

import 'models/enums.dart';
import 'report_service.dart';

const _eurFmt = r'#,##0.00 €';
const _blue = '#1565C0';
const _headBg = '#E3F2FD';
const _green = '#2E7D32';
const _red = '#C62828';

double _euros(int cents) => cents / 100.0;

String _typeLabel(TransactionType t) => switch (t) {
      TransactionType.income => 'Ingreso',
      TransactionType.expense => 'Gasto',
      TransactionType.transfer => 'Transferencia',
    };

/// Escritor secuencial de filas sobre una hoja de Syncfusion.
class _W {
  _W(this.sheet);
  final Worksheet sheet;
  int row = 1;

  Range _cell(int col) => sheet.getRangeByIndex(row, col);

  void blank() => row++;

  /// Título de sección (negrita, azul).
  void title(String text) {
    final r = _cell(1)..setText(text);
    r.cellStyle.bold = true;
    r.cellStyle.fontSize = 13;
    r.cellStyle.fontColor = _blue;
    row++;
  }

  /// Cabecera de tabla (negrita, fondo azul claro). Devuelve la fila usada.
  int header(List<String> cells) {
    for (var c = 0; c < cells.length; c++) {
      final r = sheet.getRangeByIndex(row, c + 1)..setText(cells[c]);
      r.cellStyle.bold = true;
      r.cellStyle.backColor = _headBg;
    }
    final used = row;
    row++;
    return used;
  }

  void _money(int col, int cents) {
    final r = _cell(col)..setNumber(_euros(cents));
    r.numberFormat = _eurFmt;
    r.cellStyle.hAlign = HAlignType.right;
  }

  /// Fila etiqueta + importe (+ % opcional del total).
  void labelAmount(String label, int cents, {int? total, bool pct = false}) {
    _cell(1).setText(label);
    _money(2, cents);
    if (pct) {
      final r = _cell(3);
      if (total != null && total != 0) {
        r.setNumber(cents / total);
        r.numberFormat = '0.0%';
      } else {
        r.setText('—');
      }
      r.cellStyle.hAlign = HAlignType.right;
    }
    row++;
  }

  /// Fila de total con fórmula =SUM sobre la columna [col] entre dos filas.
  void totalRow(String label, int col, int firstRow, int lastRow) {
    final l = _cell(1)..setText(label);
    l.cellStyle.bold = true;
    final letter = _colLetter(col);
    final r = _cell(col)..setFormula('=SUM($letter$firstRow:$letter$lastRow)');
    r.numberFormat = _eurFmt;
    r.cellStyle.bold = true;
    r.cellStyle.hAlign = HAlignType.right;
    row++;
  }
}

String _colLetter(int col) {
  var c = col;
  var s = '';
  while (c > 0) {
    final rem = (c - 1) % 26;
    s = String.fromCharCode(65 + rem) + s;
    c = (c - 1) ~/ 26;
  }
  return s;
}

/// Aplica formato condicional a un rango (verde si > 0, rojo si < 0).
void _signColors(Worksheet sheet, int firstRow, int lastRow, int col) {
  if (lastRow < firstRow) return;
  final range = sheet.getRangeByIndex(firstRow, col, lastRow, col);
  final formats = range.conditionalFormats;
  final green = formats.addCondition();
  green.formatType = ExcelCFType.cellValue;
  green.operator = ExcelComparisonOperator.greater;
  green.firstFormula = '0';
  green.fontColor = _green;
  final red = formats.addCondition();
  red.formatType = ExcelCFType.cellValue;
  red.operator = ExcelComparisonOperator.less;
  red.firstFormula = '0';
  red.fontColor = _red;
}

/// Genera el .xlsx del informe con Syncfusion XlsIO y lo escribe a temporal.
Future<File> buildReportExcel(ReportData data) async {
  final o = data.options;
  final df = DateFormat('yyyy-MM-dd', 'es');

  final workbook = Workbook();
  var createdCount = 0;
  Worksheet newSheet(String name) {
    final Worksheet s;
    if (createdCount == 0) {
      s = workbook.worksheets[0];
      s.name = name;
    } else {
      s = workbook.worksheets.addWithName(name);
    }
    createdCount++;
    return s;
  }

  // --- Hoja Resumen (KPIs) ---
  {
    final s = newSheet('Resumen');
    final w = _W(s);
    w.title('Informe Finanzas');
    w.blank();
    w.title('Resumen del periodo');
    if (o.flow.showsIncome) w.labelAmount('Ingresos', data.totalIncome);
    if (o.flow.showsExpense) w.labelAmount('Gastos', data.totalExpense);
    if (o.flow == ReportFlow.both) {
      w.labelAmount('Neto', data.net);
      final r = s.getRangeByIndex(w.row, 1)..setText('Ahorro');
      r.cellStyle.bold = false;
      final v = s.getRangeByIndex(w.row, 2)..setNumber(data.savingsRate / 100);
      v.numberFormat = '0.0%';
      v.cellStyle.hAlign = HAlignType.right;
      w.row++;
    }
    if (o.comparison && data.comparison != null) {
      w.blank();
      w.title('Comparativa con el periodo anterior');
      w.header(const ['', 'Actual', 'Anterior']);
      final c = data.comparison!;
      if (o.flow.showsIncome) {
        w.labelAmount('Ingresos', data.totalIncome);
        s.getRangeByIndex(w.row - 1, 3).setNumber(_euros(c.income));
        s.getRangeByIndex(w.row - 1, 3).numberFormat = _eurFmt;
      }
      if (o.flow.showsExpense) {
        w.labelAmount('Gastos', data.totalExpense);
        s.getRangeByIndex(w.row - 1, 3).setNumber(_euros(c.expense));
        s.getRangeByIndex(w.row - 1, 3).numberFormat = _eurFmt;
      }
      if (o.flow == ReportFlow.both) {
        w.labelAmount('Neto', data.net);
        s.getRangeByIndex(w.row - 1, 3).setNumber(_euros(c.net));
        s.getRangeByIndex(w.row - 1, 3).numberFormat = _eurFmt;
      }
    }
    if (data.categoryExpenses.isNotEmpty) {
      w.blank();
      final top = o.amountSort == AmountSort.desc
          ? data.categoryExpenses.first
          : data.categoryExpenses.last;
      w.labelAmount('Categoría con más gasto: ${top.label}', top.cents);
    }
    if (data.accountUsage.isNotEmpty) {
      final top = data.accountUsage.first;
      final r = s.getRangeByIndex(w.row, 1)
        ..setText('Cuenta más usada: ${top.label} (${top.count} mov.)');
      r.cellStyle.fontColor = '#455A64';
      w.row++;
    }
    s.getRangeByIndex(1, 1, 1, 3).columnWidth = 26;
    s.getRangeByIndex(1, 1).columnWidth = 32;
  }

  // --- Hoja Balance ---
  if (o.balance) {
    final s = newSheet('Balance');
    final w = _W(s);
    if (data.accountBalances.isNotEmpty) {
      w.title('Saldo por cuenta');
      w.header(const ['Cuenta', 'Saldo actual']);
      final first = w.row;
      for (final a in data.accountBalances) {
        w.labelAmount(a.label, a.cents);
      }
      _signColors(s, first, w.row - 1, 2);
      w.blank();
    }
    if (data.categoryExpenses.isNotEmpty) {
      w.title('Gasto por categoría');
      w.header(const ['Categoría', 'Gasto', '%']);
      final first = w.row;
      for (final c in data.categoryExpenses) {
        w.labelAmount(c.label, c.cents,
            total: data.totalExpense, pct: o.showPercentages);
      }
      w.totalRow('Total', 2, first, w.row - 1);
    }
    s.getRangeByIndex(1, 1).columnWidth = 28;
    s.getRangeByIndex(1, 2).columnWidth = 16;
  }

  // --- Hoja Análisis (secciones extra por cuenta / categoría / concepto) ---
  final wantsAnalysis = o.incomeByCategory ||
      o.expenseByAccount ||
      o.incomeByAccount ||
      o.accountUsage ||
      o.topConcepts;
  if (wantsAnalysis) {
    final s = newSheet('Análisis');
    final w = _W(s);

    void amountTable(String header, List<LabeledAmount> items, int total,
        String firstColHead) {
      if (items.isEmpty) return;
      w.title(header);
      w.header([firstColHead, 'Importe', if (o.showPercentages) '%']);
      final first = w.row;
      for (final e in items) {
        w.labelAmount(e.label, e.cents,
            total: total, pct: o.showPercentages);
      }
      w.totalRow('Total', 2, first, w.row - 1);
      w.blank();
    }

    if (o.incomeByCategory) {
      amountTable('Ingreso por categoría', data.categoryIncomes,
          data.totalIncome, 'Categoría');
    }
    if (o.expenseByAccount) {
      amountTable('Gasto por cuenta', data.expenseByAccount, data.totalExpense,
          'Cuenta');
    }
    if (o.incomeByAccount) {
      amountTable('Ingreso por cuenta', data.incomeByAccount, data.totalIncome,
          'Cuenta');
    }
    if (o.topConcepts && data.topConcepts.isNotEmpty) {
      amountTable('Dónde más gastas', data.topConcepts, data.totalExpense,
          'Categoría');
    }
    if (o.accountUsage && data.accountUsage.isNotEmpty) {
      w.title('Cuenta más usada');
      w.header(const ['Cuenta', 'Nº mov.', 'Volumen']);
      for (final u in data.accountUsage) {
        s.getRangeByIndex(w.row, 1).setText(u.label);
        final n = s.getRangeByIndex(w.row, 2)..setNumber(u.count.toDouble());
        n.cellStyle.hAlign = HAlignType.right;
        final v = s.getRangeByIndex(w.row, 3)..setNumber(_euros(u.volumeCents));
        v.numberFormat = _eurFmt;
        v.cellStyle.hAlign = HAlignType.right;
        w.row++;
      }
      w.blank();
    }
    s.getRangeByIndex(1, 1).columnWidth = 28;
    s.getRangeByIndex(1, 2).columnWidth = 16;
    s.getRangeByIndex(1, 3).columnWidth = 14;
  }

  // --- Hoja Evolución ---
  if (o.evolution && data.evolution.isNotEmpty) {
    final s = newSheet('Evolución');
    final w = _W(s);
    final cols = <String>[
      'Periodo',
      if (o.flow.showsIncome) 'Ingresos',
      if (o.flow.showsExpense) 'Gastos',
      if (o.flow == ReportFlow.both) 'Neto',
    ];
    w.header(cols);
    final first = w.row;
    for (final r in data.evolution) {
      var col = 1;
      s.getRangeByIndex(w.row, col++).setText(r.label);
      if (o.flow.showsIncome) w._money(col++, r.income);
      if (o.flow.showsExpense) w._money(col++, r.expense);
      if (o.flow == ReportFlow.both) w._money(col++, r.net);
      w.row++;
    }
    // Fila de totales por columna de importe.
    final last = w.row - 1;
    var col = 2;
    if (o.flow.showsIncome) {
      _totalFormula(s, w.row, col, first, last);
      col++;
    }
    if (o.flow.showsExpense) {
      _totalFormula(s, w.row, col, first, last);
      col++;
    }
    if (o.flow == ReportFlow.both) {
      _totalFormula(s, w.row, col, first, last);
      _signColors(s, first, last, col); // colorea el Neto
    }
    s.getRangeByIndex(w.row, 1).setText('Total');
    s.getRangeByIndex(w.row, 1).cellStyle.bold = true;
    s.getRangeByIndex(1, 1).columnWidth = 22;
    s.getRangeByIndex(2, 1).freezePanes();
  }

  // --- Hoja Movimientos ---
  if (o.movements) {
    final s = newSheet('Movimientos');
    final w = _W(s);
    w.header(const [
      'Fecha',
      'Tipo',
      'Concepto',
      'Categoría',
      'Cuenta',
      'Importe',
    ]);
    final first = w.row;
    for (final t in data.movements) {
      s.getRangeByIndex(w.row, 1).setText(df.format(t.date));
      s.getRangeByIndex(w.row, 2).setText(_typeLabel(t.type));
      s.getRangeByIndex(w.row, 3).setText(t.concept);
      s.getRangeByIndex(w.row, 4).setText(t.categoryId == null
          ? ''
          : (data.categoryNames[t.categoryId] ?? ''));
      s.getRangeByIndex(w.row, 5).setText(data.accountNames[t.accountId] ?? '');
      w._money(6, t.signedCents);
      w.row++;
    }
    final last = w.row - 1;
    if (last >= first) {
      _signColors(s, first, last, 6);
      // Total con fórmula.
      s.getRangeByIndex(w.row, 5).setText('Total');
      s.getRangeByIndex(w.row, 5).cellStyle.bold = true;
      _totalFormula(s, w.row, 6, first, last);
      // Autofiltro + congelar cabecera.
      s.autoFilters.filterRange = s.getRangeByIndex(1, 1, last, 6);
      s.getRangeByIndex(2, 1).freezePanes();
    }
    s.getRangeByIndex(1, 3).columnWidth = 28;
    s.getRangeByIndex(1, 4).columnWidth = 18;
    s.getRangeByIndex(1, 5).columnWidth = 18;
    s.getRangeByIndex(1, 6).columnWidth = 14;
  }

  final dir = await getTemporaryDirectory();
  final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
  final file =
      File('${dir.path}/finanzas_informe_${o.flow.fileSlug}_$stamp.xlsx');
  final bytes = workbook.saveAsStream();
  workbook.dispose();
  await file.writeAsBytes(bytes);
  return file;
}

void _totalFormula(
    Worksheet s, int row, int col, int firstRow, int lastRow) {
  final letter = _colLetter(col);
  final r = s.getRangeByIndex(row, col)
    ..setFormula('=SUM($letter$firstRow:$letter$lastRow)');
  r.numberFormat = _eurFmt;
  r.cellStyle.bold = true;
  r.cellStyle.hAlign = HAlignType.right;
}
