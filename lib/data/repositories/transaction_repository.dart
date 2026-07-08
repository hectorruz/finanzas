import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../../core/db/isar_provider.dart';
import '../../core/sync/sync_stamp.dart';
import '../models/enums.dart';
import '../models/transaction.dart';
import 'account_repository.dart';

/// Criterios de filtrado y ordenación de movimientos (filtros "tipo Excel").
class TransactionFilter {
  final DateTime? from;
  final DateTime? to;
  final Set<TransactionType> types;
  final Set<int> accountIds;
  final Set<int> categoryIds;
  final int? minCents;
  final int? maxCents;
  final String query;
  final TransactionSort sort;

  const TransactionFilter({
    this.from,
    this.to,
    this.types = const {},
    this.accountIds = const {},
    this.categoryIds = const {},
    this.minCents,
    this.maxCents,
    this.query = '',
    this.sort = TransactionSort.dateDesc,
  });

  bool get isEmpty =>
      from == null &&
      to == null &&
      types.isEmpty &&
      accountIds.isEmpty &&
      categoryIds.isEmpty &&
      minCents == null &&
      maxCents == null &&
      query.trim().isEmpty;

  TransactionFilter copyWith({
    DateTime? from,
    DateTime? to,
    Set<TransactionType>? types,
    Set<int>? accountIds,
    Set<int>? categoryIds,
    int? minCents,
    int? maxCents,
    String? query,
    TransactionSort? sort,
    bool clearDates = false,
    bool clearAmounts = false,
  }) {
    return TransactionFilter(
      from: clearDates ? null : (from ?? this.from),
      to: clearDates ? null : (to ?? this.to),
      types: types ?? this.types,
      accountIds: accountIds ?? this.accountIds,
      categoryIds: categoryIds ?? this.categoryIds,
      minCents: clearAmounts ? null : (minCents ?? this.minCents),
      maxCents: clearAmounts ? null : (maxCents ?? this.maxCents),
      query: query ?? this.query,
      sort: sort ?? this.sort,
    );
  }
}

enum TransactionSort { dateDesc, dateAsc, amountDesc, amountAsc }

class TransactionRepository {
  TransactionRepository(this._isar);
  final Isar _isar;

  Stream<void> get changes =>
      _isar.transactions.watchLazy(fireImmediately: true);

  Future<TransactionModel?> getById(int id) => _isar.transactions.get(id);

  Future<int> save(TransactionModel txn) {
    stampForSave(txn);
    return _isar.writeTxn(() => _isar.transactions.put(txn));
  }

  /// Borrado lógico (tombstone): marca [deletedAt] en vez de borrar físicamente,
  /// para que el borrado se propague en la sincronización y no "resucite".
  Future<void> delete(int id) {
    return _isar.writeTxn(() async {
      final t = await _isar.transactions.get(id);
      if (t == null) return;
      stampForDelete(t);
      await _isar.transactions.put(t);
    });
  }

  Future<void> deleteMany(List<int> ids) {
    return _isar.writeTxn(() async {
      final now = DateTime.now();
      for (final id in ids) {
        final t = await _isar.transactions.get(id);
        if (t == null) continue;
        stampForDelete(t, now: now);
        await _isar.transactions.put(t);
      }
    });
  }

  /// Actualiza en lote la categoría de varios movimientos (edición tipo Excel).
  Future<void> bulkSetCategory(List<int> ids, int? categoryId) async {
    await _isar.writeTxn(() async {
      final now = DateTime.now();
      for (final id in ids) {
        final t = await _isar.transactions.get(id);
        if (t == null) continue;
        t.categoryId = categoryId;
        stampForSave(t, now: now);
        await _isar.transactions.put(t);
      }
    });
  }

  /// Mueve en lote varios movimientos a otra cuenta.
  Future<void> bulkSetAccount(List<int> ids, int accountId) async {
    await _isar.writeTxn(() async {
      final now = DateTime.now();
      for (final id in ids) {
        final t = await _isar.transactions.get(id);
        if (t == null) continue;
        t.accountId = accountId;
        stampForSave(t, now: now);
        await _isar.transactions.put(t);
      }
    });
  }

  Future<List<TransactionModel>> recent({int limit = 10}) {
    return _isar.transactions
        .filter()
        .deletedAtIsNull()
        .sortByDateDesc()
        .limit(limit)
        .findAll();
  }

  /// Aplica un [TransactionFilter]. El rango de fechas, tipo e importe se
  /// resuelven en Isar; búsqueda de texto, cuenta y categoría se afinan en
  /// memoria (el conjunto de datos personal es pequeño).
  Future<List<TransactionModel>> query(TransactionFilter f) async {
    final all = await _isar.transactions.filter().deletedAtIsNull().findAll();
    final query = f.query.trim().toLowerCase();

    final filtered = all.where((t) {
      if (f.from != null && t.date.isBefore(f.from!)) return false;
      if (f.to != null && t.date.isAfter(f.to!)) return false;
      if (f.types.isNotEmpty && !f.types.contains(t.type)) return false;
      if (f.accountIds.isNotEmpty &&
          !f.accountIds.contains(t.accountId) &&
          !(t.toAccountId != null && f.accountIds.contains(t.toAccountId))) {
        return false;
      }
      if (f.categoryIds.isNotEmpty &&
          (t.categoryId == null || !f.categoryIds.contains(t.categoryId))) {
        return false;
      }
      if (f.minCents != null && t.amountCents < f.minCents!) return false;
      if (f.maxCents != null && t.amountCents > f.maxCents!) return false;
      if (query.isNotEmpty &&
          !t.concept.toLowerCase().contains(query) &&
          !t.note.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }).toList();

    switch (f.sort) {
      case TransactionSort.dateDesc:
        filtered.sort((a, b) => b.date.compareTo(a.date));
      case TransactionSort.dateAsc:
        filtered.sort((a, b) => a.date.compareTo(b.date));
      case TransactionSort.amountDesc:
        filtered.sort((a, b) => b.amountCents.compareTo(a.amountCents));
      case TransactionSort.amountAsc:
        filtered.sort((a, b) => a.amountCents.compareTo(b.amountCents));
    }
    return filtered;
  }

  /// Suma con signo de los movimientos en un rango (para comparativas).
  Future<({int income, int expense})> totalsBetween(
    DateTime from,
    DateTime to,
  ) async {
    final txns = await _isar.transactions
        .filter()
        .deletedAtIsNull()
        .dateBetween(from, to)
        .findAll();
    var income = 0;
    var expense = 0;
    for (final t in txns) {
      if (t.type == TransactionType.income) income += t.amountCents;
      if (t.type == TransactionType.expense) expense += t.amountCents;
    }
    return (income: income, expense: expense);
  }
}

final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => TransactionRepository(ref.watch(isarProvider)),
);

/// Filtro activo de la pantalla de movimientos.
final transactionFilterProvider =
    StateProvider<TransactionFilter>((ref) => const TransactionFilter());

/// Lista de movimientos filtrada y reactiva.
final filteredTransactionsProvider =
    FutureProvider<List<TransactionModel>>((ref) async {
  ref.watch(transactionsChangedProvider);
  final filter = ref.watch(transactionFilterProvider);
  return ref.watch(transactionRepositoryProvider).query(filter);
});

/// Últimos movimientos para el dashboard.
final recentTransactionsProvider =
    FutureProvider<List<TransactionModel>>((ref) async {
  ref.watch(transactionsChangedProvider);
  return ref.watch(transactionRepositoryProvider).recent(limit: 8);
});

/// Movimiento individual por id, reactivo (se refresca al volver del editor).
final transactionByIdProvider =
    FutureProvider.family<TransactionModel?, int>((ref, id) async {
  ref.watch(transactionsChangedProvider);
  return ref.watch(transactionRepositoryProvider).getById(id);
});
