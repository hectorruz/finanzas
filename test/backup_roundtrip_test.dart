import 'dart:convert';

import 'package:finanzas/data/backup_service.dart';
import 'package:finanzas/data/models/account.dart';
import 'package:finanzas/data/models/transaction.dart';
import 'package:finanzas/data/repositories/account_repository.dart';
import 'package:finanzas/data/repositories/transaction_repository.dart';
import 'package:isar_community/isar.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_isar.dart';

/// Verifica que el backup conserva los campos de sincronización y que un backup
/// antiguo (v1, sin uuid) se importa generando uuids.
void main() {
  setUpAll(initTestIsarCore);

  late Isar isar;
  late BackupService backup;
  setUp(() async {
    isar = await openTestIsar();
    backup = BackupService(isar);
  });
  tearDown(() async => isar.close(deleteFromDisk: true));

  test('export → import conserva uuid/updatedAt/deletedAt', () async {
    final accounts = AccountRepository(isar);
    final txns = TransactionRepository(isar);
    final accId = await accounts.save(Account()..name = 'Banco');
    final txId = await txns.save(TransactionModel()
      ..concept = 'Café'
      ..amountCents = 250
      ..accountId = accId
      ..date = DateTime(2026, 6, 1));
    // Un movimiento borrado (tombstone) debe preservarse en el backup.
    final delId = await txns.save(TransactionModel()
      ..concept = 'Borrado'
      ..amountCents = 999
      ..accountId = accId
      ..date = DateTime(2026, 6, 2));
    await txns.delete(delId);

    final original = await isar.transactions.get(txId);
    final originalDeleted = await isar.transactions.get(delId);

    final json = await backup.exportJson();
    await backup.importJson(json); // reimporta sobre la misma BD

    final restored = await isar.transactions.get(txId);
    expect(restored!.uuid, original!.uuid);
    expect(restored.updatedAt, original.updatedAt);
    expect(restored.deletedAt, isNull);

    final restoredDeleted = await isar.transactions.get(delId);
    expect(restoredDeleted!.uuid, originalDeleted!.uuid);
    expect(restoredDeleted.deletedAt, isNotNull);
  });

  test('un backup v1 sin uuid se importa generando uuids', () async {
    final legacy = jsonEncode({
      'version': 1,
      'accounts': [
        {'id': 1, 'name': 'Banco', 'type': 'bank'}
      ],
      'transactions': [
        {
          'id': 1,
          'type': 'expense',
          'amountCents': 500,
          'concept': 'Legacy',
          'date': DateTime(2026, 6, 1).toIso8601String(),
          'accountId': 1,
        }
      ],
    });

    await backup.importJson(legacy);

    final t = (await isar.transactions.where().findAll()).single;
    expect(t.uuid, isNotEmpty);
    expect(t.deletedAt, isNull);
    final a = (await isar.accounts.where().findAll()).single;
    expect(a.uuid, isNotEmpty);
  });
}
