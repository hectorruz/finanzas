import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../../core/db/isar_provider.dart';
import '../../core/sync/sync_stamp.dart';
import '../../features/accounts/deposit_math.dart';
import '../models/account.dart';
import '../models/enums.dart';
import '../models/transaction.dart';
import 'tree.dart';

class AccountRepository {
  AccountRepository(this._isar);
  final Isar _isar;

  Future<List<Account>> all({bool includeArchived = false}) {
    if (includeArchived) {
      return _isar.accounts
          .filter()
          .deletedAtIsNull()
          .sortBySortOrder()
          .findAll();
    }
    return _isar.accounts
        .filter()
        .deletedAtIsNull()
        .archivedEqualTo(false)
        .sortBySortOrder()
        .findAll();
  }

  Stream<List<Account>> watchActive() {
    return _isar.accounts
        .filter()
        .deletedAtIsNull()
        .archivedEqualTo(false)
        .sortBySortOrder()
        .watch(fireImmediately: true);
  }

  Future<Account?> getById(int id) => _isar.accounts.get(id);

  Future<int> save(Account account) {
    stampForSave(account);
    return _isar.writeTxn(() => _isar.accounts.put(account));
  }

  Future<void> archive(int id, {bool archived = true}) async {
    await _isar.writeTxn(() async {
      final acc = await _isar.accounts.get(id);
      if (acc == null) return;
      acc.archived = archived;
      stampForSave(acc);
      await _isar.accounts.put(acc);
    });
  }

  /// Borra (lógicamente) una cuenta y todos sus movimientos asociados (origen o
  /// destino). Sus subcuentas directas se recolocan bajo el padre de la borrada
  /// (su "abuelo"), conservando el resto del árbol en lugar de quedar huérfanas.
  /// Todo se marca como tombstone (`deletedAt`) en vez de borrarse físicamente,
  /// para que el borrado se propague en la sincronización.
  Future<void> delete(int id) async {
    await _isar.writeTxn(() async {
      final now = DateTime.now();
      final deleted = await _isar.accounts.get(id);
      if (deleted == null) return;

      final children =
          await _isar.accounts.filter().parentIdEqualTo(id).findAll();
      for (final c in children) {
        c.parentId = deleted.parentId;
        stampForSave(c, now: now); // el re-parenting es una modificación
      }
      if (children.isNotEmpty) await _isar.accounts.putAll(children);

      final related = await _isar.transactions
          .filter()
          .accountIdEqualTo(id)
          .or()
          .toAccountIdEqualTo(id)
          .findAll();
      for (final t in related) {
        stampForDelete(t, now: now);
      }
      if (related.isNotEmpty) await _isar.transactions.putAll(related);

      stampForDelete(deleted, now: now);
      await _isar.accounts.put(deleted);
    });
  }

  /// Calcula el saldo actual de una cuenta: saldo inicial + movimientos.
  Future<int> balanceCents(int accountId) async {
    final acc = await _isar.accounts.get(accountId);
    if (acc == null) return 0;
    var total = acc.initialBalanceCents;

    final outgoing = await _isar.transactions
        .filter()
        .deletedAtIsNull()
        .accountIdEqualTo(accountId)
        .findAll();
    for (final t in outgoing) {
      total += t.signedCents;
    }

    // Transferencias entrantes (la cuenta es destino) suman el importe.
    final incoming = await _isar.transactions
        .filter()
        .deletedAtIsNull()
        .typeEqualTo(TransactionType.transfer)
        .toAccountIdEqualTo(accountId)
        .findAll();
    for (final t in incoming) {
      total += t.amountCents;
    }

    // Interés neto (depósitos) / ganancia bruta (letras) proyectados de todo
    // depósito o Letra del Tesoro cuyo banco efectivo sea esta cuenta. Es una
    // estimación fija hasta el vencimiento; la propia cuenta del depósito sigue
    // aportando solo su capital, así que no hay doble conteo.
    final linked = await _isar.accounts
        .filter()
        .deletedAtIsNull()
        .group((q) => q
            .typeEqualTo(AccountType.deposit)
            .or()
            .typeEqualTo(AccountType.treasuryBill))
        .findAll();
    for (final d in linked) {
      if (d.holdingBankId != accountId) continue;
      total += projectedBankCreditCents(
        type: d.type,
        principalOrPurchaseCents: d.initialBalanceCents,
        rateBps: d.depositRateBps,
        nominalCents: d.nominalCents,
        start: d.depositStartDate,
        end: d.depositEndDate,
      );
    }
    return total;
  }
}

/// Aplana las cuentas en un árbol de anidamiento ilimitado (subcuentas dentro
/// de subcuentas), con la profundidad de cada nodo.
List<TreeEntry<Account>> flattenAccounts(List<Account> all) => flattenTree(
      all,
      idOf: (a) => a.id,
      parentIdOf: (a) => a.parentId,
    );

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
