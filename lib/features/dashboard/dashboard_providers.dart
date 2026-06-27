import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/account.dart';
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

/// Una fila de la tarjeta "Balance por cuentas": la cuenta, su profundidad en el
/// árbol (0 = primer nivel) y su saldo **agregado** (saldo propio más el de sus
/// subcuentas mostradas).
class AccountCardRow {
  const AccountCardRow({
    required this.account,
    required this.depth,
    required this.rolledCents,
  });
  final Account account;
  final int depth;
  final int rolledCents;
}

/// Filas de la tarjeta "Balance por cuentas", en orden de árbol e indentadas por
/// profundidad. Cada cuenta muestra su saldo propio más el de sus descendientes
/// presentes en el conjunto mostrado (agregado solo visual: el balance total no
/// se ve afectado). Si en ajustes no se filtra ninguna cuenta, se muestran todas
/// las activas; si se filtra, solo esas (el agregado suma los descendientes que
/// también se muestran).
final accountsCardRowsProvider =
    FutureProvider<List<AccountCardRow>>((ref) async {
  ref.watch(transactionsChangedProvider);
  final accountRepo = ref.watch(accountRepositoryProvider);
  final settings = ref.watch(currentSettingsProvider);
  final all = await ref.watch(accountsProvider.future);

  final ids = settings.accountsCardIds.toSet();
  final shown =
      ids.isEmpty ? all : all.where((a) => ids.contains(a.id)).toList();
  if (shown.isEmpty) return const [];

  // Saldo propio de cada cuenta mostrada.
  final ownCents = <int, int>{};
  for (final a in shown) {
    ownCents[a.id] = await accountRepo.balanceCents(a.id);
  }

  // Hijos directos por padre, restringido a las cuentas mostradas.
  final shownIds = shown.map((a) => a.id).toSet();
  final childrenOf = <int, List<int>>{};
  for (final a in shown) {
    final p = a.parentId;
    if (p != null && shownIds.contains(p)) {
      childrenOf.putIfAbsent(p, () => []).add(a.id);
    }
  }

  // Saldo agregado = propio + suma de descendientes mostrados (recursivo).
  final rolled = <int, int>{};
  int rolledFor(int id) {
    final cached = rolled[id];
    if (cached != null) return cached;
    var total = ownCents[id] ?? 0;
    for (final childId in childrenOf[id] ?? const []) {
      total += rolledFor(childId);
    }
    return rolled[id] = total;
  }

  return [
    for (final entry in flattenAccounts(shown))
      AccountCardRow(
        account: entry.value,
        depth: entry.depth,
        rolledCents: rolledFor(entry.value.id),
      ),
  ];
});

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
