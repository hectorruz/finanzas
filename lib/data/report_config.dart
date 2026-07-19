import 'dart:convert';

import 'models/enums.dart';

/// Opciones y configuración del informe: puro Dart, sin Isar. Vive separado
/// de `report_service.dart` (que sí importa Isar para `ReportService`/
/// `ReportData`) a propósito, para que la webapp de escritorio pueda
/// importarlo sin arrastrar los modelos Isar a la compilación web — sus
/// esquemas generados (`*.g.dart`) usan ids `int64` como literales que
/// `dart2js` no puede representar, así que cualquier import transitivo de
/// Isar rompe `flutter build web`. Ver la nota de CLAUDE.md sobre mantener
/// móvil y webapp sincronizados: este fichero es el que ambos comparten.

/// Granularidad de la sección de evolución del informe.
enum EvolutionGranularity { weekly, monthly, yearly }

/// Claves de tarjeta disponibles para la portada personalizable del informe
/// (ver `lib/data/report_cover_cards.dart` para etiquetas/iconos del editor).
/// Vive aquí (y no en el catálogo con `IconData`) para que este fichero, sin
/// dependencia de Flutter Material, siga siendo el único origen de verdad del
/// valor por defecto que usan tanto el editor como `ReportConfig.decode`.
const kDefaultReportCoverCards = <String>[
  'kpiIncome',
  'kpiExpense',
  'kpiNet',
  'kpiSavingsRate',
  'kpiBiggestExpense',
  'kpiTopCategory',
  'kpiTopAccount',
  'chartCategoryPie',
];

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
    this.coverCards = kDefaultReportCoverCards,
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

  /// Qué tarjetas (KPIs/gráficos/análisis) muestra la portada dashboard, y en
  /// qué orden. Claves de `kReportCoverCatalog`; una clave desconocida (versión
  /// antigua tras quitar un tipo de tarjeta) se ignora al renderizar.
  final List<String> coverCards;

  /// Tarjetas efectivas de la portada: si [coverCards] está vacía se usan las
  /// de por defecto, igual que hace el editor (`ReportCoverCardsEditor`). Así el
  /// editor y el generador coinciden: vaciar las tarjetas **no** deja una
  /// portada en blanco (para quitar la portada se usa [dashboardPage]).
  List<String> get effectiveCoverCards =>
      coverCards.isEmpty ? kDefaultReportCoverCards : coverCards;

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
    this.coverCards = kDefaultReportCoverCards,
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
  final List<String> coverCards;

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
    List<String>? coverCards,
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
        coverCards: coverCards ?? this.coverCards,
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
        coverCards: coverCards,
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
        'coverCards': coverCards,
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
      List<String> strings(String key, List<String> def) {
        final raw = m[key] as List<dynamic>?;
        if (raw == null) return def;
        return raw.map((e) => e as String).toList();
      }

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
        coverCards: strings('coverCards', kDefaultReportCoverCards),
      );
    } catch (_) {
      return const ReportConfig();
    }
  }
}
