import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:isar_community/isar.dart';

import '../core/db/isar_provider.dart';
import 'models/account.dart';
import 'models/category.dart';
import 'models/enums.dart';
import 'models/transaction.dart';
import 'repositories/account_repository.dart';

/// Granularidad de la sección de evolución del informe.
enum EvolutionGranularity { weekly, monthly, yearly }

/// Qué flujos de movimientos incluir en el informe.
enum ReportFlow { income, expense, both }

/// Orden de las tablas de importes (categorías, cuentas, conceptos).
enum AmountSort { desc, asc }

/// Orden del listado de movimientos.
enum MovementSort { dateDesc, dateAsc, amountDesc, amountAsc }

extension ReportFlowLabel on ReportFlow {
  String get label => switch (this) {
        ReportFlow.income => 'Ingresos',
        ReportFlow.expense => 'Gastos',
        ReportFlow.both => 'Ambos',
      };

  /// ¿Debe incluirse un movimiento de este tipo según el flujo seleccionado?
  bool includes(TransactionType type) => switch (this) {
        ReportFlow.income => type == TransactionType.income,
        ReportFlow.expense => type == TransactionType.expense,
        ReportFlow.both => true,
      };

  /// ¿El informe muestra la columna/fila de ingresos?
  bool get showsIncome => this != ReportFlow.expense;

  /// ¿El informe muestra la columna/fila de gastos?
  bool get showsExpense => this != ReportFlow.income;

  /// Fragmento para el nombre del archivo generado.
  String get fileSlug => switch (this) {
        ReportFlow.income => 'ingresos',
        ReportFlow.expense => 'gastos',
        ReportFlow.both => 'completo',
      };
}

extension EvolutionGranularityLabel on EvolutionGranularity {
  String get label => switch (this) {
        EvolutionGranularity.weekly => 'Semanal',
        EvolutionGranularity.monthly => 'Mensual',
        EvolutionGranularity.yearly => 'Anual',
      };
}

extension AmountSortLabel on AmountSort {
  String get label => switch (this) {
        AmountSort.desc => 'Mayor a menor',
        AmountSort.asc => 'Menor a mayor',
      };
}

extension MovementSortLabel on MovementSort {
  String get label => switch (this) {
        MovementSort.dateDesc => 'Fecha ↓',
        MovementSort.dateAsc => 'Fecha ↑',
        MovementSort.amountDesc => 'Importe ↓',
        MovementSort.amountAsc => 'Importe ↑',
      };
}

/// Qué incluye el informe y para qué tramo de fechas.
class ReportOptions {
  ReportOptions({
    required this.from,
    required this.to,
    this.flow = ReportFlow.both,
    this.granularity = EvolutionGranularity.monthly,
    this.amountSort = AmountSort.desc,
    this.movementSort = MovementSort.dateAsc,
    this.accountIds = const [],
    this.categoryIds = const [],
    this.includeArchived = false,
    this.showPercentages = true,
    // Secciones
    this.dashboardPage = true,
    this.balance = true,
    this.evolution = true,
    this.movements = true,
    this.incomeByCategory = false,
    this.expenseByAccount = false,
    this.incomeByAccount = false,
    this.accountUsage = false,
    this.topConcepts = false,
    this.comparison = false,
    this.averages = false,
    // Gráficos (solo PDF)
    this.pieChart = true,
    this.barChart = true,
  });

  final DateTime from;
  final DateTime to;
  final ReportFlow flow;
  final EvolutionGranularity granularity;

  final AmountSort amountSort;
  final MovementSort movementSort;

  /// Filtro de cuentas (vacío = todas).
  final List<int> accountIds;

  /// Filtro de categorías (vacío = todas).
  final List<int> categoryIds;

  /// Incluir cuentas archivadas en saldos y análisis por cuenta.
  final bool includeArchived;

  /// Mostrar columna de % del total en las tablas de reparto.
  final bool showPercentages;

  // --- Secciones ---
  final bool dashboardPage;
  final bool balance;
  final bool evolution;
  final bool movements;
  final bool incomeByCategory;
  final bool expenseByAccount;
  final bool incomeByAccount;
  final bool accountUsage;
  final bool topConcepts;
  final bool comparison;
  final bool averages;

  // --- Gráficos ---
  final bool pieChart;
  final bool barChart;

  /// ¿Hay alguna sección seleccionada?
  bool get anySection =>
      dashboardPage ||
      balance ||
      evolution ||
      movements ||
      incomeByCategory ||
      expenseByAccount ||
      incomeByAccount ||
      accountUsage ||
      topConcepts ||
      comparison ||
      averages;
}

/// Configuración persistente del informe (todo salvo el rango de fechas, que es
/// puntual). Se serializa en [AppSettings.reportConfig].
class ReportConfig {
  const ReportConfig({
    this.flow = ReportFlow.both,
    this.granularity = EvolutionGranularity.monthly,
    this.amountSort = AmountSort.desc,
    this.movementSort = MovementSort.dateAsc,
    this.accountIds = const [],
    this.categoryIds = const [],
    this.includeArchived = false,
    this.showPercentages = true,
    this.dashboardPage = true,
    this.balance = true,
    this.evolution = true,
    this.movements = true,
    this.incomeByCategory = false,
    this.expenseByAccount = false,
    this.incomeByAccount = false,
    this.accountUsage = false,
    this.topConcepts = false,
    this.comparison = false,
    this.averages = false,
    this.pieChart = true,
    this.barChart = true,
  });

  final ReportFlow flow;
  final EvolutionGranularity granularity;
  final AmountSort amountSort;
  final MovementSort movementSort;
  final List<int> accountIds;
  final List<int> categoryIds;
  final bool includeArchived;
  final bool showPercentages;
  final bool dashboardPage;
  final bool balance;
  final bool evolution;
  final bool movements;
  final bool incomeByCategory;
  final bool expenseByAccount;
  final bool incomeByAccount;
  final bool accountUsage;
  final bool topConcepts;
  final bool comparison;
  final bool averages;
  final bool pieChart;
  final bool barChart;

  ReportConfig copyWith({
    ReportFlow? flow,
    EvolutionGranularity? granularity,
    AmountSort? amountSort,
    MovementSort? movementSort,
    List<int>? accountIds,
    List<int>? categoryIds,
    bool? includeArchived,
    bool? showPercentages,
    bool? dashboardPage,
    bool? balance,
    bool? evolution,
    bool? movements,
    bool? incomeByCategory,
    bool? expenseByAccount,
    bool? incomeByAccount,
    bool? accountUsage,
    bool? topConcepts,
    bool? comparison,
    bool? averages,
    bool? pieChart,
    bool? barChart,
  }) =>
      ReportConfig(
        flow: flow ?? this.flow,
        granularity: granularity ?? this.granularity,
        amountSort: amountSort ?? this.amountSort,
        movementSort: movementSort ?? this.movementSort,
        accountIds: accountIds ?? this.accountIds,
        categoryIds: categoryIds ?? this.categoryIds,
        includeArchived: includeArchived ?? this.includeArchived,
        showPercentages: showPercentages ?? this.showPercentages,
        dashboardPage: dashboardPage ?? this.dashboardPage,
        balance: balance ?? this.balance,
        evolution: evolution ?? this.evolution,
        movements: movements ?? this.movements,
        incomeByCategory: incomeByCategory ?? this.incomeByCategory,
        expenseByAccount: expenseByAccount ?? this.expenseByAccount,
        incomeByAccount: incomeByAccount ?? this.incomeByAccount,
        accountUsage: accountUsage ?? this.accountUsage,
        topConcepts: topConcepts ?? this.topConcepts,
        comparison: comparison ?? this.comparison,
        averages: averages ?? this.averages,
        pieChart: pieChart ?? this.pieChart,
        barChart: barChart ?? this.barChart,
      );

  /// Construye las opciones de un informe combinando la config con un rango.
  ReportOptions toOptions({required DateTime from, required DateTime to}) =>
      ReportOptions(
        from: from,
        to: to,
        flow: flow,
        granularity: granularity,
        amountSort: amountSort,
        movementSort: movementSort,
        accountIds: accountIds,
        categoryIds: categoryIds,
        includeArchived: includeArchived,
        showPercentages: showPercentages,
        dashboardPage: dashboardPage,
        balance: balance,
        evolution: evolution,
        movements: movements,
        incomeByCategory: incomeByCategory,
        expenseByAccount: expenseByAccount,
        incomeByAccount: incomeByAccount,
        accountUsage: accountUsage,
        topConcepts: topConcepts,
        comparison: comparison,
        averages: averages,
        pieChart: pieChart,
        barChart: barChart,
      );

  String encode() => jsonEncode({
        'flow': flow.name,
        'granularity': granularity.name,
        'amountSort': amountSort.name,
        'movementSort': movementSort.name,
        'accountIds': accountIds,
        'categoryIds': categoryIds,
        'includeArchived': includeArchived,
        'showPercentages': showPercentages,
        'dashboardPage': dashboardPage,
        'balance': balance,
        'evolution': evolution,
        'movements': movements,
        'incomeByCategory': incomeByCategory,
        'expenseByAccount': expenseByAccount,
        'incomeByAccount': incomeByAccount,
        'accountUsage': accountUsage,
        'topConcepts': topConcepts,
        'comparison': comparison,
        'averages': averages,
        'pieChart': pieChart,
        'barChart': barChart,
      });

  /// Decodifica una config; devuelve los valores por defecto si el JSON es
  /// inválido o está vacío.
  static ReportConfig decode(String raw) {
    if (raw.isEmpty) return const ReportConfig();
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      List<int> ids(String key) => (m[key] as List<dynamic>? ?? const [])
          .map((e) => (e as num).toInt())
          .toList();
      bool flag(String key, bool def) => m[key] as bool? ?? def;
      return ReportConfig(
        flow: enumByName(ReportFlow.values, m['flow'] as String?, ReportFlow.both),
        granularity: enumByName(EvolutionGranularity.values,
            m['granularity'] as String?, EvolutionGranularity.monthly),
        amountSort: enumByName(
            AmountSort.values, m['amountSort'] as String?, AmountSort.desc),
        movementSort: enumByName(MovementSort.values,
            m['movementSort'] as String?, MovementSort.dateAsc),
        accountIds: ids('accountIds'),
        categoryIds: ids('categoryIds'),
        includeArchived: flag('includeArchived', false),
        showPercentages: flag('showPercentages', true),
        dashboardPage: flag('dashboardPage', true),
        balance: flag('balance', true),
        evolution: flag('evolution', true),
        movements: flag('movements', true),
        incomeByCategory: flag('incomeByCategory', false),
        expenseByAccount: flag('expenseByAccount', false),
        incomeByAccount: flag('incomeByAccount', false),
        accountUsage: flag('accountUsage', false),
        topConcepts: flag('topConcepts', false),
        comparison: flag('comparison', false),
        averages: flag('averages', false),
        pieChart: flag('pieChart', true),
        barChart: flag('barChart', true),
      );
    } catch (_) {
      return const ReportConfig();
    }
  }
}

/// Una fila de la evolución temporal (un periodo).
class EvolutionRow {
  EvolutionRow(this.start, this.label);
  final DateTime start;
  final String label;
  int income = 0;
  int expense = 0;
  int get net => income - expense;
}

/// Importe etiquetado (saldo por cuenta, gasto por categoría…).
typedef LabeledAmount = ({String label, int cents});

/// Uso de una cuenta en el periodo: nº de movimientos y volumen movido.
typedef AccountUsage = ({String label, int count, int volumeCents});

/// Movimiento destacado (mayor gasto / mayor ingreso).
typedef ExtremeMovement = ({String concept, int cents, DateTime date});

/// Totales del periodo anterior equivalente, para la comparativa.
class ReportComparison {
  const ReportComparison({required this.income, required this.expense});
  final int income;
  final int expense;
  int get net => income - expense;
}

/// Medias y récords del periodo.
class ReportAverages {
  const ReportAverages({
    required this.avgDailyExpense,
    required this.avgMonthlyExpense,
    required this.avgDailyIncome,
    required this.maxExpense,
    required this.maxIncome,
  });
  final int avgDailyExpense;
  final int avgMonthlyExpense;
  final int avgDailyIncome;
  final ExtremeMovement? maxExpense;
  final ExtremeMovement? maxIncome;
}

/// Datos ya calculados de un informe, listos para renderizar a PDF/Excel.
class ReportData {
  ReportData({
    required this.options,
    required this.movements,
    required this.accountNames,
    required this.categoryNames,
    required this.totalIncome,
    required this.totalExpense,
    required this.accountBalances,
    required this.categoryExpenses,
    required this.categoryIncomes,
    required this.expenseByAccount,
    required this.incomeByAccount,
    required this.accountUsage,
    required this.topConcepts,
    required this.evolution,
    required this.comparison,
    required this.averages,
  });

  final ReportOptions options;

  /// Movimientos del rango, según el orden elegido.
  final List<TransactionModel> movements;
  final Map<int, String> accountNames;
  final Map<int, String> categoryNames;

  // Balance del periodo (transferencias excluidas de ingresos/gastos).
  final int totalIncome;
  final int totalExpense;
  int get net => totalIncome - totalExpense;

  /// Porcentaje de ahorro sobre los ingresos (0..100); 0 si no hay ingresos.
  double get savingsRate =>
      totalIncome <= 0 ? 0 : (net / totalIncome) * 100;

  /// Saldo **actual** de cada cuenta (todo el histórico).
  final List<LabeledAmount> accountBalances;

  /// Gasto por categoría en el rango.
  final List<LabeledAmount> categoryExpenses;

  /// Ingreso por categoría en el rango.
  final List<LabeledAmount> categoryIncomes;

  /// Gasto por cuenta en el rango (transferencias excluidas).
  final List<LabeledAmount> expenseByAccount;

  /// Ingreso por cuenta en el rango.
  final List<LabeledAmount> incomeByAccount;

  /// Uso de cada cuenta (nº de movimientos y volumen) en el rango.
  final List<AccountUsage> accountUsage;

  /// Conceptos donde más se gasta en el rango.
  final List<LabeledAmount> topConcepts;

  final List<EvolutionRow> evolution;

  /// Totales del periodo anterior equivalente (null si no se pidió).
  final ReportComparison? comparison;

  /// Medias y récords del periodo (null si no se pidió).
  final ReportAverages? averages;
}

/// Calcula los datos de un informe a partir de la base de datos.
class ReportService {
  ReportService(this._isar);
  final Isar _isar;

  Future<ReportData> build(ReportOptions o) async {
    final txns = await _query(o.from, o.to, o);

    // Nombres de todas las cuentas y categorías (incluye archivadas, para poder
    // resolver el nombre de cualquier movimiento).
    final allAccounts = await _isar.accounts.where().findAll();
    allAccounts.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final categories = await _isar.categories.where().findAll();
    final accountNames = {for (final a in allAccounts) a.id: a.name};
    final categoriesById = {for (final c in categories) c.id: c};
    final categoryNames = {
      for (final c in categories) c.id: categoryFullName(c.id, categoriesById)
    };

    // Cuentas a listar en saldos/análisis por cuenta.
    final listedAccounts = allAccounts
        .where((a) => o.includeArchived || !a.archived)
        .where((a) => o.accountIds.isEmpty || o.accountIds.contains(a.id))
        .toList();

    // --- Totales y acumuladores por categoría / cuenta / concepto ---
    var income = 0;
    var expense = 0;
    final expenseByCat = <int?, int>{};
    final incomeByCat = <int?, int>{};
    final expenseByAcc = <int, int>{};
    final incomeByAcc = <int, int>{};
    final conceptAcc = <String, ({String display, int cents})>{};
    final usageCount = <int, int>{};
    final usageVolume = <int, int>{};
    ExtremeMovement? maxExpense;
    ExtremeMovement? maxIncome;

    for (final t in txns) {
      usageCount.update(t.accountId, (v) => v + 1, ifAbsent: () => 1);
      usageVolume.update(t.accountId, (v) => v + t.amountCents,
          ifAbsent: () => t.amountCents);

      if (t.type == TransactionType.income) {
        income += t.amountCents;
        incomeByCat.update(t.categoryId, (v) => v + t.amountCents,
            ifAbsent: () => t.amountCents);
        incomeByAcc.update(t.accountId, (v) => v + t.amountCents,
            ifAbsent: () => t.amountCents);
        if (maxIncome == null || t.amountCents > maxIncome.cents) {
          maxIncome = (concept: t.concept, cents: t.amountCents, date: t.date);
        }
      } else if (t.type == TransactionType.expense) {
        expense += t.amountCents;
        expenseByCat.update(t.categoryId, (v) => v + t.amountCents,
            ifAbsent: () => t.amountCents);
        expenseByAcc.update(t.accountId, (v) => v + t.amountCents,
            ifAbsent: () => t.amountCents);
        final key = t.concept.trim().toLowerCase();
        final display = t.concept.trim().isEmpty ? 'Sin concepto' : t.concept.trim();
        conceptAcc.update(key, (v) => (display: v.display, cents: v.cents + t.amountCents),
            ifAbsent: () => (display: display, cents: t.amountCents));
        if (maxExpense == null || t.amountCents > maxExpense.cents) {
          maxExpense = (concept: t.concept, cents: t.amountCents, date: t.date);
        }
      }
    }

    // Saldo actual por cuenta.
    final accountRepo = AccountRepository(_isar);
    final accountBalances = <LabeledAmount>[];
    for (final a in listedAccounts) {
      accountBalances
          .add((label: a.name, cents: await accountRepo.balanceCents(a.id)));
    }

    String catLabel(int? id) => id == null
        ? 'Sin categoría'
        : (categoryNames[id] ?? 'Categoría #$id');
    String accLabel(int id) => accountNames[id] ?? 'Cuenta #$id';

    final categoryExpenses = _sortedLabeled(
        expenseByCat.entries.map((e) => (label: catLabel(e.key), cents: e.value)),
        o.amountSort);
    final categoryIncomes = _sortedLabeled(
        incomeByCat.entries.map((e) => (label: catLabel(e.key), cents: e.value)),
        o.amountSort);
    final expenseByAccount = _sortedLabeled(
        expenseByAcc.entries.map((e) => (label: accLabel(e.key), cents: e.value)),
        o.amountSort);
    final incomeByAccount = _sortedLabeled(
        incomeByAcc.entries.map((e) => (label: accLabel(e.key), cents: e.value)),
        o.amountSort);
    // Top conceptos: siempre los 15 de mayor gasto, luego se ordenan para mostrar.
    final topConcepts = (conceptAcc.values
            .map((v) => (label: v.display, cents: v.cents))
            .toList()
          ..sort((a, b) => b.cents.compareTo(a.cents)))
        .take(15)
        .toList();
    if (o.amountSort == AmountSort.asc) {
      topConcepts.sort((a, b) => a.cents.compareTo(b.cents));
    }

    // Uso por cuenta (orden por nº de movimientos desc).
    final accountUsage = usageCount.entries
        .map((e) => (
              label: accLabel(e.key),
              count: e.value,
              volumeCents: usageVolume[e.key] ?? 0,
            ))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    final evolution = _buildEvolution(txns, o.granularity);

    // Comparativa con el periodo anterior equivalente.
    ReportComparison? comparison;
    if (o.comparison) {
      final span = o.to.difference(o.from);
      final prevTo = o.from.subtract(const Duration(milliseconds: 1));
      final prevFrom = prevTo.subtract(span);
      final prevTxns = await _query(prevFrom, prevTo, o);
      var pi = 0, pe = 0;
      for (final t in prevTxns) {
        if (t.type == TransactionType.income) pi += t.amountCents;
        if (t.type == TransactionType.expense) pe += t.amountCents;
      }
      comparison = ReportComparison(income: pi, expense: pe);
    }

    // Medias y récords.
    ReportAverages? averages;
    if (o.averages) {
      final days = o.to.difference(o.from).inDays + 1;
      final safeDays = days <= 0 ? 1 : days;
      averages = ReportAverages(
        avgDailyExpense: expense ~/ safeDays,
        avgDailyIncome: income ~/ safeDays,
        avgMonthlyExpense: (expense * 30) ~/ safeDays,
        maxExpense: maxExpense,
        maxIncome: maxIncome,
      );
    }

    return ReportData(
      options: o,
      movements: txns,
      accountNames: accountNames,
      categoryNames: categoryNames,
      totalIncome: income,
      totalExpense: expense,
      accountBalances: accountBalances,
      categoryExpenses: categoryExpenses,
      categoryIncomes: categoryIncomes,
      expenseByAccount: expenseByAccount,
      incomeByAccount: incomeByAccount,
      accountUsage: accountUsage,
      topConcepts: topConcepts,
      evolution: evolution,
      comparison: comparison,
      averages: averages,
    );
  }

  /// Consulta y filtra los movimientos de un rango según las opciones, ya
  /// ordenados según [ReportOptions.movementSort].
  Future<List<TransactionModel>> _query(
      DateTime from, DateTime to, ReportOptions o) async {
    final txns = (await _isar.transactions
            .filter()
            .deletedAtIsNull()
            .dateBetween(from, to)
            .findAll())
        .where((t) => o.flow.includes(t.type))
        .where((t) =>
            o.accountIds.isEmpty ||
            o.accountIds.contains(t.accountId) ||
            (t.toAccountId != null && o.accountIds.contains(t.toAccountId)))
        .where((t) =>
            o.categoryIds.isEmpty ||
            (t.categoryId != null && o.categoryIds.contains(t.categoryId)))
        .toList();
    _sortMovements(txns, o.movementSort);
    return txns;
  }

  void _sortMovements(List<TransactionModel> txns, MovementSort sort) {
    switch (sort) {
      case MovementSort.dateAsc:
        txns.sort((a, b) => a.date.compareTo(b.date));
      case MovementSort.dateDesc:
        txns.sort((a, b) => b.date.compareTo(a.date));
      case MovementSort.amountAsc:
        txns.sort((a, b) => a.amountCents.compareTo(b.amountCents));
      case MovementSort.amountDesc:
        txns.sort((a, b) => b.amountCents.compareTo(a.amountCents));
    }
  }

  List<LabeledAmount> _sortedLabeled(
      Iterable<LabeledAmount> items, AmountSort sort) {
    final list = items.toList();
    list.sort((a, b) => sort == AmountSort.desc
        ? b.cents.compareTo(a.cents)
        : a.cents.compareTo(b.cents));
    return list;
  }

  List<EvolutionRow> _buildEvolution(
    List<TransactionModel> txns,
    EvolutionGranularity g,
  ) {
    final buckets = <DateTime, EvolutionRow>{};
    for (final t in txns) {
      if (t.type == TransactionType.transfer) continue;
      final start = _bucketStart(t.date, g);
      final row = buckets.putIfAbsent(
          start, () => EvolutionRow(start, _bucketLabel(start, g)));
      if (t.type == TransactionType.income) row.income += t.amountCents;
      if (t.type == TransactionType.expense) row.expense += t.amountCents;
    }
    final rows = buckets.values.toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return rows;
  }

  DateTime _bucketStart(DateTime d, EvolutionGranularity g) {
    switch (g) {
      case EvolutionGranularity.weekly:
        final monday = d.subtract(Duration(days: d.weekday - 1));
        return DateTime(monday.year, monday.month, monday.day);
      case EvolutionGranularity.monthly:
        return DateTime(d.year, d.month, 1);
      case EvolutionGranularity.yearly:
        return DateTime(d.year, 1, 1);
    }
  }

  String _bucketLabel(DateTime start, EvolutionGranularity g) {
    switch (g) {
      case EvolutionGranularity.weekly:
        return 'Sem. ${DateFormat('d MMM yyyy', 'es').format(start)}';
      case EvolutionGranularity.monthly:
        return DateFormat('MMMM yyyy', 'es').format(start);
      case EvolutionGranularity.yearly:
        return DateFormat('yyyy', 'es').format(start);
    }
  }
}

final reportServiceProvider =
    Provider<ReportService>((ref) => ReportService(ref.watch(isarProvider)));
