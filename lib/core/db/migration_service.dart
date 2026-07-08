import 'package:isar_community/isar.dart';

import '../../data/models/account.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/category.dart';
import '../../data/models/goal.dart';
import '../../data/models/receipt.dart';
import '../../data/models/recurring_rule.dart';
import '../../data/models/transaction.dart';
import '../sync/sync_stamp.dart';
import '../sync/syncable.dart';

/// Versión actual del esquema de datos. Se guarda en `AppSettings.dataVersion`
/// y determina qué backfills quedan por aplicar.
///
/// - v1: campos de sincronización (uuid/updatedAt/deletedAt) añadidos a las
///   colecciones de dominio; backfill de uuid y updatedAt de las filas previas.
const int kCurrentDataVersion = 1;

/// Ejecuta las migraciones de datos pendientes de forma **idempotente**.
///
/// Se invoca en `IsarService.open()`, justo tras abrir la BD, de modo que corre
/// tanto en `main()` como en `quickAddMain()` sin duplicar trabajo. El guard por
/// `AppSettings.dataVersion` dentro del `writeTxn` lo hace seguro frente al
/// acceso multi-isolate del quick-add: quien llegue primero migra y avanza la
/// versión; el resto ve `dataVersion == kCurrentDataVersion` y no hace nada.
Future<void> runMigrations(Isar isar) async {
  await isar.writeTxn(() async {
    final settings = await isar.settings.get(0) ?? (AppSettings()..id = 0);

    if (settings.dataVersion < 1) {
      await _backfillSyncFields(isar);
    }

    if (settings.dataVersion != kCurrentDataVersion) {
      settings.dataVersion = kCurrentDataVersion;
      await isar.settings.put(settings);
    }
  });
}

/// v1: asigna `uuid` y `updatedAt` a toda fila que aún no los tenga (las creadas
/// antes de existir estos campos). Deja `deletedAt` en null (todas están vivas).
/// Debe ejecutarse dentro de un `writeTxn`.
Future<void> _backfillSyncFields(Isar isar) async {
  final now = DateTime.now();

  Future<void> backfill<T extends Syncable>(
    IsarCollection<T> collection,
    Future<List<T>> Function() loadPending,
  ) async {
    final pending = await loadPending();
    if (pending.isEmpty) return;
    for (final entity in pending) {
      // Reutiliza el sellado central; genera uuid solo si falta y fija updatedAt.
      stampForSave(entity, now: now);
    }
    await collection.putAll(pending);
  }

  await backfill(
      isar.accounts, () => isar.accounts.filter().uuidEqualTo('').findAll());
  await backfill(isar.categories,
      () => isar.categories.filter().uuidEqualTo('').findAll());
  await backfill(isar.transactions,
      () => isar.transactions.filter().uuidEqualTo('').findAll());
  await backfill(isar.recurringRules,
      () => isar.recurringRules.filter().uuidEqualTo('').findAll());
  await backfill(
      isar.receipts, () => isar.receipts.filter().uuidEqualTo('').findAll());
  await backfill(
      isar.goals, () => isar.goals.filter().uuidEqualTo('').findAll());
}
