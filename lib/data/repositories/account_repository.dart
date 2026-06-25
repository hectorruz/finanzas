import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../../core/db/isar_provider.dart';
import '../models/account.dart';
import '../models/enums.dart';
import '../models/transaction.dart';

class AccountRepository {
  AccountRepository(this._isar);
  final Isar _isar;

  Future<List<Account>> all({bool includeArchived = false}) {
    if (includeArchived) {
      return _isar.accounts.where().sortBySortOrder().findAll();
    }
    return _isar.accounts
        .filter()
        .archivedEqualTo(false)
        .sortBySortOrder()
        .findAll();
  }

  Stream<List<Account>> watchActive() {
    return _isar.accounts
        .filter()
        .archivedEqualTo(false)
        .sortBySortOrder()
        .watch(fireImmediately: true);
  }

  Future<Account?> getById(int id) => _isar.accounts.get(id);

  Future<int> save(Account account) {
    return _isar.writeTxn(() => _isar.accounts.put(account));
  }

  Future<void> archive(int id, {bool archived = true}) async {
    await _isar.writeTxn(() async {
      final acc = await _isar.accounts.get(id);
      if (acc == null) return;
      acc.archived = archived;
      await _isar.accounts.put(acc);
    });
  }

  /// Borra una cuenta y todos sus movimientos asociados (origen o destino).
  Future<void> delete(int id) async {
    await _isar.writeTxn(() async {
      final related = await _isar.transactions
          .filter()
          .accountIdEqualTo(id)
          .or()
          .toAccountIdEqualTo(id)
          .findAll();
      await _isar.transactions
          .deleteAll(related.map((t) => t.id).toList());
      await _isar.accounts.delete(id);
    });
  }

  /// Calcula el saldo actual de una cuenta: saldo inicial + movimientos.
  Future<int> balanceCents(int accountId) async {
    final acc = await _isar.accounts.get(accountId);
    if (acc == null) return 0;
    var total = acc.initialBalanceCents;

    final outgoing = await _isar.transactions
        .filter()
        .accountIdEqualTo(accountId)
        .findAll();
    for (final t in outgoing) {
      total += t.signedCents;
    }

    // Transferencias entrantes (la cuenta es destino) suman el importe.
    final incoming = await _isar.transactions
        .filter()
        .typeEqualTo(TransactionType.transfer)
        .toAccountIdEqualTo(accountId)
        .findAll();
    for (final t in incoming) {
      total += t.amountCents;
    }
    return total;
  }
}

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(ref.watch(isarProvider)),
);

/// Lista reactiva de cuentas activas.
final accountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchActive(),
);

/// "Tick" que emite cuando cambian los movimientos, para invalidar cálculos
/// derivados (saldos, balances del dashboard).
final transactionsChangedProvider = StreamProvider<void>((ref) {
  final isar = ref.watch(isarProvider);
  return isar.transactions.watchLazy(fireImmediately: true);
});

/// Saldo de una cuenta concreta (se recalcula al cambiar movimientos/cuentas).
final accountBalanceProvider =
    FutureProvider.family<int, int>((ref, accountId) async {
  ref.watch(accountsProvider);
  ref.watch(transactionsChangedProvider);
  return ref.watch(accountRepositoryProvider).balanceCents(accountId);
});
