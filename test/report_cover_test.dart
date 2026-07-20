import 'package:finanzas/data/report_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Construye un [ReportData] mínimo para probar la resolución de la portada.
/// Solo se parametrizan los campos que afectan a `coverCardHasContent`.
ReportData _data({
  ReportFlow flow = ReportFlow.both,
  List<String> coverCards = kDefaultReportCoverCards,
  bool pieChart = true,
  bool barChart = true,
  int totalIncome = 0,
  int totalExpense = 0,
  List<LabeledAmount> categoryExpenses = const [],
  List<AccountUsage> accountUsage = const [],
  List<EvolutionRow> evolution = const [],
  ExtremeMovement? maxExpense,
  ReportComparison? comparison,
  ReportAverages? averages,
}) =>
    ReportData(
      options: ReportOptions(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 31),
        flow: flow,
        pieChart: pieChart,
        barChart: barChart,
        coverCards: coverCards,
      ),
      movements: const [],
      accountNames: const {},
      categoryNames: const {},
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      accountBalances: const [],
      categoryExpenses: categoryExpenses,
      categoryIncomes: const [],
      expenseByAccount: const [],
      incomeByAccount: const [],
      accountUsage: accountUsage,
      topConcepts: const [],
      evolution: evolution,
      comparison: comparison,
      averages: averages,
      maxExpense: maxExpense,
    );

void main() {
  final from = DateTime(2026, 1, 1);
  final to = DateTime(2026, 12, 31);

  group('ReportOptions.effectiveCoverCards', () {
    test('lista vacía → tarjetas por defecto (portada no queda en blanco)', () {
      final o = ReportOptions(from: from, to: to, coverCards: const []);
      expect(o.effectiveCoverCards, kDefaultReportCoverCards);
    });

    test('lista con contenido se respeta tal cual', () {
      final o = ReportOptions(
        from: from,
        to: to,
        coverCards: const ['kpiIncome', 'kpiExpense'],
      );
      expect(o.effectiveCoverCards, const ['kpiIncome', 'kpiExpense']);
    });

    test('config con coverCards vacío llega a las opciones como vacío pero '
        'effectiveCoverCards lo rescata', () {
      // Simula el estado que dejaba la portada en blanco: el usuario ocultó
      // todas las tarjetas y se persistió coverCards: [].
      const cfg = ReportConfig(coverCards: []);
      final o = cfg.toOptions(from: from, to: to);
      expect(o.coverCards, isEmpty);
      expect(o.effectiveCoverCards, kDefaultReportCoverCards);
    });
  });

  group('resolveCoverCards', () {
    test('una selección aplicable se respeta tal cual', () {
      final d = _data(
        coverCards: const ['kpiIncome', 'kpiExpense'],
        totalIncome: 100,
        totalExpense: 50,
      );
      expect(resolveCoverCards(d), const ['kpiIncome', 'kpiExpense']);
    });

    test('selección toda inaplicable al flujo → recae en las por defecto', () {
      // Solo KPIs de ingresos/neto/ahorro, pero con flujo de solo gastos:
      // antes esto dejaba la portada con solo el encabezado.
      final d = _data(
        flow: ReportFlow.expense,
        coverCards: const ['kpiIncome', 'kpiNet', 'kpiSavingsRate'],
        totalExpense: 500,
      );
      final r = resolveCoverCards(d);
      expect(r, isNotEmpty);
      expect(r, contains('kpiExpense'));
      // Las inaplicables siguen fuera (kpiIncome no aplica a flujo "Gastos").
      expect(r, isNot(contains('kpiIncome')));
    });

    test('tarjetas de análisis sin datos → recae en las por defecto', () {
      final d = _data(
        coverCards: const [
          'kpiTopCategory',
          'kpiTopAccount',
          'chartCategoryPie',
          'blockTopCategories',
        ],
      );
      final r = resolveCoverCards(d);
      expect(r, isNotEmpty);
      expect(r, containsAll(<String>['kpiIncome', 'kpiExpense']));
    });

    test('por defecto con flujo "ambos" y sin datos ya muestra los KPIs base',
        () {
      final r = resolveCoverCards(_data());
      expect(
        r,
        containsAll(
            <String>['kpiIncome', 'kpiExpense', 'kpiNet', 'kpiSavingsRate']),
      );
    });

    test('Excel (excludeCharts) descarta una selección de solo gráficos', () {
      // El gráfico SÍ aplicaría en PDF (hay gasto por categoría), pero Excel no
      // pinta gráficos → debe recaer en las por defecto para no quedar en blanco.
      final d = _data(
        coverCards: const ['chartCategoryPie'],
        categoryExpenses: const [(label: 'Comida', cents: 100)],
      );
      expect(resolveCoverCards(d), const ['chartCategoryPie']); // PDF respeta
      final excel = resolveCoverCards(d, excludeCharts: true);
      expect(excel, isNot(contains('chartCategoryPie')));
      expect(excel, contains('kpiIncome'));
    });
  });

  group('coverCardHasContent', () {
    test('neto/ahorro solo tienen contenido con flujo "ambos"', () {
      expect(coverCardHasContent('kpiNet', _data(flow: ReportFlow.both)), isTrue);
      expect(
          coverCardHasContent('kpiNet', _data(flow: ReportFlow.expense)), isFalse);
      expect(coverCardHasContent('kpiSavingsRate', _data(flow: ReportFlow.income)),
          isFalse);
    });

    test('ingresos/gastos dependen solo del flujo (aunque el total sea 0)', () {
      expect(coverCardHasContent('kpiIncome', _data(flow: ReportFlow.income)),
          isTrue);
      expect(coverCardHasContent('kpiIncome', _data(flow: ReportFlow.expense)),
          isFalse);
      expect(coverCardHasContent('kpiExpense', _data(flow: ReportFlow.income)),
          isFalse);
    });

    test('"mayor gasto" necesita un gasto máximo', () {
      expect(coverCardHasContent('kpiBiggestExpense', _data()), isFalse);
      expect(
        coverCardHasContent('kpiBiggestExpense',
            _data(maxExpense: (concept: 'X', cents: 10, date: DateTime(2026)))),
        isTrue,
      );
    });

    test('el gráfico circular necesita pieChart activo, datos y no excludeCharts',
        () {
      final withCats =
          _data(categoryExpenses: const [(label: 'A', cents: 1)]);
      expect(coverCardHasContent('chartCategoryPie', withCats), isTrue);
      expect(
          coverCardHasContent('chartCategoryPie', withCats, excludeCharts: true),
          isFalse);
      expect(
        coverCardHasContent(
            'chartCategoryPie',
            _data(
                pieChart: false,
                categoryExpenses: const [(label: 'A', cents: 1)])),
        isFalse,
      );
    });

    test('una clave desconocida nunca tiene contenido', () {
      expect(coverCardHasContent('claveInventada', _data()), isFalse);
    });
  });
}
