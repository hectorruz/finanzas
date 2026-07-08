import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../../core/db/isar_provider.dart';
import '../../core/sync/sync_stamp.dart';
import '../models/receipt.dart';

class ReceiptRepository {
  ReceiptRepository(this._isar);
  final Isar _isar;

  Stream<List<Receipt>> watchAll() {
    return _isar.receipts
        .filter()
        .deletedAtIsNull()
        .sortByDateDesc()
        .watch(fireImmediately: true);
  }

  Future<List<Receipt>> all() =>
      _isar.receipts.filter().deletedAtIsNull().sortByDateDesc().findAll();

  Future<Receipt?> getById(int id) => _isar.receipts.get(id);

  Future<int> save(Receipt receipt) {
    stampForSave(receipt);
    return _isar.writeTxn(() => _isar.receipts.put(receipt));
  }

  /// Borrado lógico (tombstone) para que se propague en la sincronización.
  Future<void> delete(int id) {
    return _isar.writeTxn(() async {
      final r = await _isar.receipts.get(id);
      if (r == null) return;
      stampForDelete(r);
      await _isar.receipts.put(r);
    });
  }

  Future<void> deleteMany(List<int> ids) {
    return _isar.writeTxn(() async {
      final now = DateTime.now();
      for (final id in ids) {
        final r = await _isar.receipts.get(id);
        if (r == null) continue;
        stampForDelete(r, now: now);
        await _isar.receipts.put(r);
      }
    });
  }
}

final receiptRepositoryProvider = Provider<ReceiptRepository>(
  (ref) => ReceiptRepository(ref.watch(isarProvider)),
);

final receiptsProvider = StreamProvider<List<Receipt>>(
  (ref) => ref.watch(receiptRepositoryProvider).watchAll(),
);

/// Ticket individual por id, reactivo (se refresca al cambiar la lista).
final receiptByIdProvider = FutureProvider.family<Receipt?, int>((ref, id) {
  ref.watch(receiptsProvider);
  return ref.watch(receiptRepositoryProvider).getById(id);
});

/// Estadísticas de gasto por comercio (top de comercios donde más se gasta).
final merchantStatsProvider =
    FutureProvider<List<({String merchant, int totalCents, int count})>>(
        (ref) async {
  final receipts = await ref.watch(receiptRepositoryProvider).all();
  final byMerchant = <String, ({int total, int count})>{};
  for (final r in receipts) {
    final key = r.merchant.trim().isEmpty ? 'Desconocido' : r.merchant.trim();
    final prev = byMerchant[key] ?? (total: 0, count: 0);
    byMerchant[key] = (total: prev.total + r.totalCents, count: prev.count + 1);
  }
  final list = byMerchant.entries
      .map((e) =>
          (merchant: e.key, totalCents: e.value.total, count: e.value.count))
      .toList()
    ..sort((a, b) => b.totalCents.compareTo(a.totalCents));
  return list;
});
