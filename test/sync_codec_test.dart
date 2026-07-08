import 'package:finanzas/data/models/account.dart';
import 'package:finanzas/data/models/enums.dart';
import 'package:finanzas/data/models/transaction.dart';
import 'package:finanzas/features/sync/model/entity_change.dart';
import 'package:finanzas/features/sync/sync_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// El codec traduce las FKs int locales a uuids al codificar y de vuelta a ids
/// (distintos) al aplicar, sin perder datos.
void main() {
  const codec = SyncCodec();

  test('codifica una cuenta resolviendo parentUuid', () {
    final child = Account()
      ..uuid = 'child'
      ..name = 'Hija'
      ..parentId = 1
      ..updatedAt = DateTime(2026, 1, 1);

    // En el dispositivo local, la cuenta 1 tiene uuid 'parent'.
    String? uuidOf(SyncCollection c, int? id) =>
        (c == SyncCollection.account && id == 1) ? 'parent' : null;

    final change = codec.encodeAccount(child, uuidOf);
    expect(change.data['parentUuid'], 'parent');
    expect(change.data['name'], 'Hija');
  });

  test('roundtrip de transacción: las FKs sobreviven con ids locales distintos',
      () {
    final tx = TransactionModel()
      ..uuid = 'tx-1'
      ..type = TransactionType.expense
      ..amountCents = 4500
      ..concept = 'Mercadona'
      ..date = DateTime(2026, 6, 3)
      ..accountId = 1
      ..categoryId = 7
      ..updatedAt = DateTime(2026, 6, 3);

    // Origen: cuenta 1 = 'acc', categoría 7 = 'cat'.
    String? uuidOf(SyncCollection c, int? id) {
      if (c == SyncCollection.account && id == 1) return 'acc';
      if (c == SyncCollection.category && id == 7) return 'cat';
      return null;
    }

    final change = codec.encodeTransaction(tx, uuidOf);
    final json = EntityChange.fromJson(change.toJson()); // sobrevive a JSON

    // Destino: los mismos uuids mapean a ids locales DISTINTOS.
    int? idOf(SyncCollection c, String? uuid) {
      if (c == SyncCollection.account && uuid == 'acc') return 99;
      if (c == SyncCollection.category && uuid == 'cat') return 42;
      return null;
    }

    final restored = TransactionModel();
    codec.applyTransaction(restored, json, idOf);

    expect(restored.uuid, 'tx-1');
    expect(restored.amountCents, 4500);
    expect(restored.concept, 'Mercadona');
    expect(restored.date, DateTime(2026, 6, 3));
    expect(restored.accountId, 99, reason: 'FK cuenta re-resuelta al id local');
    expect(restored.categoryId, 42, reason: 'FK categoría re-resuelta');
    expect(restored.type, TransactionType.expense);
  });

  test('FK nula se mantiene nula', () {
    final tx = TransactionModel()
      ..uuid = 't'
      ..accountId = 1
      ..categoryId = null
      ..date = DateTime(2026, 1, 1);
    String? uuidOf(SyncCollection c, int? id) => id == 1 ? 'acc' : null;
    final change = codec.encodeTransaction(tx, uuidOf);
    expect(change.data['categoryUuid'], isNull);

    final restored = TransactionModel();
    codec.applyTransaction(restored, change, (c, u) => u == 'acc' ? 5 : null);
    expect(restored.categoryId, isNull);
    expect(restored.accountId, 5);
  });
}
