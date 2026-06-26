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

extension EvolutionGranularityLabel on EvolutionGranularity {
  String get label => switch (this) {
        EvolutionGranularity.weekly => 'Semanal',
        EvolutionGranularity.monthly => 'Mensual',
        EvolutionGranularity.yearly => 'Anual',
      };
}

/// Qué incluye el informe y para qué tramo de fechas.
class ReportOptions {
  ReportOptions({
    required this.from,
    required this.to,
    this.movements = true,
    this.balance = true,
    this.evolution = true,
    this.granularity = EvolutionGranularity.monthly,
  });

  final DateTime from;
  final DateTime to;
  final bool movements;
  final bool balance;
  final bool evolution;
  final EvolutionGranularity granularity;
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

/// Importe etiquetado (saldo por cuenta, gasto por categoría).
typedef LabeledAmount = ({String label, int cents});

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
    required this.evolution,
  });

  final ReportOptions options;

  /// Movimientos del rango, orden por fecha ascendente.
  final List<TransactionModel> movements;
  final Map<int, String> accountNames;
  final Map<int, String> categoryNames;

  // Balance del periodo (transferencias excluidas de ingresos/gastos).
  final int totalIncome;
  final int totalExpense;
  int get net => totalIncome - totalExpense;

  /// Saldo **actual** de cada cuenta activa.
  final List<LabeledAmount> accountBalances;

  /// Gasto por categoría en el rango, orden descendente.
  final List<LabeledAmount> categoryExpenses;

  final List<EvolutionRow> evolution;
}

/// Calcula los datos de un informe a partir de la base de datos.
class ReportService {
  ReportService(this._isar);
  final Isar _isar;

  Future<ReportData> build(ReportOptions o) async {
    final txns = await _isar.transactions
        .filter()
        .dateBetween(o.from, o.to)
        .findAll();
    txns.sort((a, b) => a.date.compareTo(b.date));

    final accounts = await _isar.accounts
        .filter()
        .archivedEqualTo(false)
        .sortBySortOrder()
        .findAll();
    final categories = await _isar.categories.where().findAll();
    final accountNames = {for (final a in accounts) a.id: a.name};
    final categoryNames = {for (final c in categories) c.id: c.name};

    // Totales del periodo (transferencias no cuentan como ingreso/gasto).
    var income = 0;
    var expense = 0;
    final categoryAcc = <int?, int>{};
    for (final t in txns) {
      if (t.type == TransactionType.income) income += t.amountCents;
      if (t.type == TransactionType.expense) {
        expense += t.amountCents;
        categoryAcc.update(t.categoryId, (v) => v + t.amountCents,
            ifAbsent: () => t.amountCents);
      }
    }

    // Saldo actual por cuenta.
    final accountRepo = AccountRepository(_isar);
    final accountBalances = <LabeledAmount>[];
    for (final a in accounts) {
      accountBalances.add((label: a.name, cents: await accountRepo.balanceCents(a.id)));
    }

    // Gasto por categoría (desc).
    final categoryExpenses = categoryAcc.entries
        .map((e) => (
              label: e.key == null
                  ? 'Sin categoría'
                  : (categoryNames[e.key] ?? 'Categoría #${e.key}'),
              cents: e.value,
            ))
        .toList()
      ..sort((a, b) => b.cents.compareTo(a.cents));

    final evolution = _buildEvolution(txns, o.granularity);

    return ReportData(
      options: o,
      movements: txns,
      accountNames: accountNames,
      categoryNames: categoryNames,
      totalIncome: income,
      totalExpense: expense,
      accountBalances: accountBalances,
      categoryExpenses: categoryExpenses,
      evolution: evolution,
    );
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
