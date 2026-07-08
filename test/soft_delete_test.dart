import 'package:finanzas/data/models/account.dart';
import 'package:finanzas/data/models/enums.dart';
import 'package:finanzas/data/models/transaction.dart';
import 'package:finanzas/data/repositories/account_repository.dart';
import 'package:finanzas/data/repositories/transaction_repository.dart';
import 'package:isar_community/isar.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_isar.dart';

/// Verifica que el borrado es lógico (tombstone): la fila desaparece de las
/// listas activas pero sigue físicamente en la BD, para poder propagar el
/// borrado en la sincronización sin que "resucite".
void main() {
  setUpAll(initTestIsarCore);

  late Isar isar;
  late TransactionRepository txns;
  late AccountRepository accounts;
  setUp(() async {
    isar = await openTestIsar();
    txns = TransactionRepository(isar);
    accounts = AccountRepository(isar);
  });
  tearDown(() async => isar.close(deleteFromDisk: true));

  test('borrar un movimiento lo marca sin borrarlo físicamente', () async {
    final accId = await accounts.save(Account()..name = 'Banco');
    final id = await txns.save(TransactionModel()
      ..concept = 'Café'
      ..amountCents = 250
      ..accountId = accId
      ..date = DateTime(2026, 6, 1));

    await txns.delete(id);

    // Excluido de las consultas activas.
    final active = await txns.query(const TransactionFilter());
    expect(active.any((t) => t.id == id), isFalse);

    // Pero sigue físicamente, con el tombstone puesto.
    final raw = await isar.transactions.get(id);
    expect(raw, isNotNull);
    expect(raw!.deletedAt, isNotNull);
    expect(raw.uuid, isNotEmpty);
  });

  test('el saldo de la cuenta ignora los movimientos borrados', () async {
    final accId = await accounts.save(Account()
      ..name = 'Banco'
      ..initialBalanceCents = 0);
    final id = await txns.save(TransactionModel()
      ..concept = 'Ingreso'
      ..amountCents = 10000
      ..accountId = accId
      ..type = TransactionType.income
      ..date = DateTime(2026, 6, 1));

    expect(await accounts.balanceCents(accId), 10000);
    await txns.delete(id);
    expect(await accounts.balanceCents(accId), 0);
  });

  test('borrar una cuenta hace soft-delete de sus movimientos y re-parenta hijos',
      () async {
    final parentId = await accounts.save(Account()..name = 'Padre');
    final childId = await accounts.save(Account()
      ..name = 'Hija'
      ..parentId = parentId);
    final txId = await txns.save(TransactionModel()
      ..concept = 'gasto'
      ..amountCents = 500
      ..accountId = parentId
      ..date = DateTime(2026, 6, 1));

    await accounts.delete(parentId);

    // La cuenta borrada: tombstone físico, ausente de activas.
    final rawAcc = await isar.accounts.get(parentId);
    expect(rawAcc!.deletedAt, isNotNull);
    final activeAccs = await accounts.all(includeArchived: true);
    expect(activeAccs.any((a) => a.id == parentId), isFalse);

    // El hijo se recoloca bajo el "abuelo" (null) y sigue vivo.
    final rawChild = await isar.accounts.get(childId);
    expect(rawChild!.parentId, isNull);
    expect(rawChild.deletedAt, isNull);

    // El movimiento de la cuenta queda como tombstone.
    final rawTx = await isar.transactions.get(txId);
    expect(rawTx!.deletedAt, isNotNull);
  });

  test('deleteMany marca todos los indicados', () async {
    final accId = await accounts.save(Account()..name = 'Banco');
    final ids = <int>[];
    for (var i = 0; i < 3; i++) {
      ids.add(await txns.save(TransactionModel()
        ..concept = 't$i'
        ..amountCents = 100
        ..accountId = accId
        ..date = DateTime(2026, 6, 1)));
    }

    await txns.deleteMany(ids);

    final active = await txns.query(const TransactionFilter());
    expect(active, isEmpty);
    for (final id in ids) {
      expect((await isar.transactions.get(id))!.deletedAt, isNotNull);
    }
  });
}
