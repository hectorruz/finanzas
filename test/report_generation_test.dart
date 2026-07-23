import 'dart:io';

import 'package:finanzas/data/models/enums.dart';
import 'package:finanzas/data/models/transaction.dart';
import 'package:finanzas/data/report_excel.dart';
import 'package:finanzas/data/report_pdf.dart';
import 'package:finanzas/data/report_service.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Fake de path_provider para que getTemporaryDirectory funcione en test.
class _FakePathProvider extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
}

TransactionModel _tx({
  required TransactionType type,
  required int cents,
  required String concept,
  required int accountId,
  int? categoryId,
  int? toAccountId,
  required DateTime date,
}) =>
    TransactionModel()
      ..type = type
      ..amountCents = cents
      ..concept = concept
      ..accountId = accountId
      ..categoryId = categoryId
      ..toAccountId = toAccountId
      ..date = date;

ReportData _sampleData() {
  final now = DateTime(2026, 6, 15);
  final movements = <TransactionModel>[
    _tx(type: TransactionType.income, cents: 250000, concept: 'Nómina', accountId: 1, categoryId: 11, date: DateTime(2026, 6, 1)),
    _tx(type: TransactionType.expense, cents: 4500, concept: 'Mercadona', accountId: 1, categoryId: 10, date: DateTime(2026, 6, 3)),
    _tx(type: TransactionType.expense, cents: 1200, concept: 'Mercadona', accountId: 2, categoryId: 10, date: DateTime(2026, 6, 8)),
    _tx(type: TransactionType.expense, cents: 8000, concept: 'Gasolina', accountId: 1, categoryId: null, date: now),
    _tx(type: TransactionType.transfer, cents: 10000, concept: 'Ahorro', accountId: 1, toAccountId: 2, date: now),
  ];
  return ReportData(
    options: ReportOptions(
      from: DateTime(2026, 6, 1),
      to: DateTime(2026, 6, 30, 23, 59, 59),
      flow: ReportFlow.both,
      granularity: EvolutionGranularity.monthly,
      dashboardPage: true,
      balance: true,
      evolution: true,
      movements: true,
      incomeByCategory: true,
      expenseByAccount: true,
      incomeByAccount: true,
      accountUsage: true,
      topConcepts: true,
      comparison: true,
      averages: true,
      pieChart: true,
      barChart: true,
      showPercentages: true,
    ),
    movements: movements,
    accountNames: {1: 'Banco', 2: 'Efectivo'},
    categoryNames: {10: 'Comida', 11: 'Nómina'},
    totalIncome: 250000,
    totalExpense: 13700,
    accountBalances: [(label: 'Banco', cents: 227500), (label: 'Efectivo', cents: 8800)],
    categoryExpenses: [(label: 'Gasolina', cents: 8000), (label: 'Comida', cents: 5700)],
    categoryIncomes: [(label: 'Nómina', cents: 250000)],
    expenseByAccount: [(label: 'Banco', cents: 12500), (label: 'Efectivo', cents: 1200)],
    incomeByAccount: [(label: 'Banco', cents: 250000)],
    accountUsage: [(label: 'Banco', count: 4, volumeCents: 272500), (label: 'Efectivo', count: 1, volumeCents: 1200)],
    topConcepts: [(label: 'Gasolina', cents: 8000), (label: 'Mercadona', cents: 5700)],
    evolution: [
      EvolutionRow(DateTime(2026, 5, 1), 'mayo 2026')
        ..income = 200000
        ..expense = 90000,
      EvolutionRow(DateTime(2026, 6, 1), 'junio 2026')
        ..income = 250000
        ..expense = 13700,
    ],
    comparison: const ReportComparison(income: 200000, expense: 90000),
    averages: ReportAverages(
      avgDailyExpense: 456,
      avgMonthlyExpense: 13700,
      avgDailyIncome: 8333,
      maxExpense: (concept: 'Gasolina', cents: 8000, date: DateTime(2026, 6, 15)),
      maxIncome: (concept: 'Nómina', cents: 250000, date: DateTime(2026, 6, 1)),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    PathProviderPlatform.instance = _FakePathProvider();
    await initializeDateFormatting('es_ES', null);
    // rootBundle necesita saber cargar las fuentes reales del asset bundle.
  });

  test('buildReportExcel genera un .xlsx no vacío', () async {
    final file = await buildReportExcel(_sampleData());
    expect(await file.exists(), isTrue);
    expect((await file.length()) > 0, isTrue);
  });

  test('buildReportPdf genera un .pdf no vacío', () async {
    // Carga real de las fuentes empaquetadas.
    final file = await buildReportPdf(_sampleData());
    expect(await file.exists(), isTrue);
    expect((await file.length()) > 0, isTrue);
  });

  test(
      'un solo periodo de evolución no degenera en NaN '
      '(regresión: informe de "Este mes" con página en blanco en release)',
      () async {
    // Con una sola barra, el eje X de FixedAxis quedaba con rango 0..0 y la
    // interpolación dividía por cero: aserción en debug, página en blanco en
    // release. Las aserciones de PdfNum siguen activas en test, así que basta
    // con que la generación complete.
    final base = _sampleData();
    final data = ReportData(
      options: ReportOptions(
        from: DateTime(2026, 6, 1),
        to: DateTime(2026, 6, 30, 23, 59, 59),
        coverCards: const ['kpiIncome', 'chartEvolutionBar'],
      ),
      movements: base.movements,
      accountNames: base.accountNames,
      categoryNames: base.categoryNames,
      totalIncome: base.totalIncome,
      totalExpense: base.totalExpense,
      accountBalances: base.accountBalances,
      categoryExpenses: base.categoryExpenses,
      categoryIncomes: base.categoryIncomes,
      expenseByAccount: base.expenseByAccount,
      incomeByAccount: base.incomeByAccount,
      accountUsage: base.accountUsage,
      topConcepts: base.topConcepts,
      evolution: [
        EvolutionRow(DateTime(2026, 6, 1), 'junio 2026')
          ..income = 250000
          ..expense = 13700,
      ],
      comparison: null,
      averages: null,
      maxExpense: base.maxExpense,
      maxIncome: base.maxIncome,
    );
    final file = await buildReportPdf(data);
    expect((await file.length()) > 0, isTrue);
  });

  test(
      'la portada pinta las tarjetas dentro de la página '
      '(regresión: stretch con altura infinita la dejaba solo con el banner)',
      () async {
    final data = _sampleData();
    final widgets = buildCoverWidgets(
        data, null, DateFormat('d MMM yyyy', 'es'));
    // Banner + separador + rejilla KPI + bloques, como mínimo.
    expect(widgets.length, greaterThanOrEqualTo(3));

    // Mismo layout que la portada real: Column dentro de una página A4. Tras
    // save(), cada widget conserva su caja de layout; con el bug de stretch,
    // la rejilla salía con altura infinita y no se pintaba nada.
    final base = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final bold =
        pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    final doc = pw.Document();
    doc.addPage(pw.Page(
      theme: pw.ThemeData.withFont(base: base, bold: bold),
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: widgets,
      ),
    ));
    await doc.save();

    for (final w in widgets) {
      expect(w.box, isNotNull);
      expect(w.box!.height.isFinite, isTrue,
          reason: 'un widget de la portada quedó con altura infinita');
      expect(w.box!.height, lessThanOrEqualTo(PdfPageFormat.a4.height));
    }
    // La rejilla de KPIs (tercer widget) ocupa espacio real.
    expect(widgets[2].box!.height, greaterThan(0));
  });
}
