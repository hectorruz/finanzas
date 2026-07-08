import 'package:finanzas/core/db/migration_service.dart';
import 'package:finanzas/data/models/account.dart';
import 'package:finanzas/data/models/app_settings.dart';
import 'package:finanzas/data/models/category.dart';
import 'package:finanzas/data/models/transaction.dart';
import 'package:isar_community/isar.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_isar.dart';

/// Verifica el backfill idempotente de los campos de sincronización sobre datos
/// creados antes de que existieran (uuid vacío / updatedAt epoch).
void main() {
  setUpAll(initTestIsarCore);

  late Isar isar;
  setUp(() async => isar = await openTestIsar());
  tearDown(() async => isar.close(deleteFromDisk: true));

  /// Inserta filas "antiguas" saltándose el sellado del repositorio, para
  /// simular una BD anterior a la migración.
  Future<void> insertLegacyRows() async {
    await isar.writeTxn(() async {
      await isar.accounts.putAll([
        Account()..name = 'Banco',
        Account()..name = 'Efectivo',
      ]);
      await isar.categories.put(Category()..name = 'Alimentación');
      await isar.transactions.putAll([
        TransactionModel()..concept = 'A',
        TransactionModel()..concept = 'B',
        TransactionModel()..concept = 'C',
      ]);
    });
  }

  test('asigna uuid único y updatedAt a las filas previas', () async {
    await insertLegacyRows();

    // Antes: todas sin uuid.
    final before = await isar.transactions.where().findAll();
    expect(before.every((t) => t.uuid.isEmpty), isTrue);

    await runMigrations(isar);

    final txns = await isar.transactions.where().findAll();
    final accounts = await isar.accounts.where().findAll();
    final cats = await isar.categories.where().findAll();
    final all = [...txns, ...accounts, ...cats];

    // Todas selladas, ninguna borrada.
    expect(all.every((e) => e.uuid.isNotEmpty), isTrue);
    expect(all.every((e) => e.updatedAt.millisecondsSinceEpoch > 0), isTrue);
    expect(all.every((e) => e.deletedAt == null), isTrue);

    // Uuids únicos en el conjunto.
    final uuids = all.map((e) => e.uuid).toSet();
    expect(uuids.length, all.length);

    // Versión de datos avanzada.
    final settings = await isar.settings.get(0);
    expect(settings?.dataVersion, kCurrentDataVersion);
  });

  test('es idempotente: una segunda pasada no cambia nada', () async {
    await insertLegacyRows();
    await runMigrations(isar);

    final snapshot = {
      for (final t in await isar.transactions.where().findAll())
        t.id: (t.uuid, t.updatedAt)
    };

    await runMigrations(isar);

    final after = await isar.transactions.where().findAll();
    for (final t in after) {
      expect(t.uuid, snapshot[t.id]!.$1, reason: 'uuid estable');
      expect(t.updatedAt, snapshot[t.id]!.$2, reason: 'updatedAt intacto');
    }
    final settings = await isar.settings.get(0);
    expect(settings?.dataVersion, kCurrentDataVersion);
  });

  test('no toca filas que ya tienen uuid (migración parcial previa)', () async {
    await isar.writeTxn(() async {
      await isar.transactions.put(TransactionModel()
        ..concept = 'ya-sellada'
        ..uuid = 'fixed-uuid'
        ..updatedAt = DateTime(2026, 5, 5));
    });

    await runMigrations(isar);

    final t = (await isar.transactions.where().findAll()).single;
    expect(t.uuid, 'fixed-uuid');
    expect(t.updatedAt, DateTime(2026, 5, 5));
  });
}
