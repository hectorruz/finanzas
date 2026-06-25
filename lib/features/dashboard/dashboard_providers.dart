import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/account_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/transaction_repository.dart';

/// Balance total (céntimos) de las cuentas seleccionadas para el total.
///
/// Si en ajustes hay cuentas elegidas explícitamente, se usan esas; si no, se
/// suman todas las que tengan `includeInTotal`.
final totalBalanceProvider = FutureProvider<int>((ref) async {
  ref.watch(transactionsChangedProvider);
  final accountRepo = ref.watch(accountRepositoryProvider);
  final settings = ref.watch(currentSettingsProvider);
  final accounts = await accountRepo.all();

  final selected = settings.totalBalanceAccountIds.toSet();
  final relevant = accounts.where((a) {
    if (selected.isNotEmpty) return selected.contains(a.id);
    return a.includeInTotal;
  });

  var total = 0;
  for (final a in relevant) {
    total += await accountRepo.balanceCents(a.id);
  }
  return total;
});

/// Comparativa de gastos del mes actual frente al mes anterior.
class MonthComparison {
  final int currentExpense;
  final int previousExpense;
  final int currentIncome;

  const MonthComparison({
    required this.currentExpense,
    required this.previousExpense,
    required this.currentIncome,
  });

  /// Variación porcentual del gasto respecto al mes anterior (null si no hay base).
  double? get expenseChangePercent {
    if (previousExpense == 0) return null;
    return (currentExpense - previousExpense) / previousExpense * 100;
  }
}

final monthComparisonProvider = FutureProvider<MonthComparison>((ref) async {
  ref.watch(transactionsChangedProvider);
  final repo = ref.watch(transactionRepositoryProvider);
  final now = DateTime.now();

  final startThis = DateTime(now.year, now.month, 1);
  final startNext = DateTime(now.year, now.month + 1, 1);
  final startPrev = DateTime(now.year, now.month - 1, 1);

  final current = await repo.totalsBetween(
    startThis,
    startNext.subtract(const Duration(milliseconds: 1)),
  );
  final previous = await repo.totalsBetween(
    startPrev,
    startThis.subtract(const Duration(milliseconds: 1)),
  );

  return MonthComparison(
    currentExpense: current.expense,
    previousExpense: previous.expense,
    currentIncome: current.income,
  );
});
