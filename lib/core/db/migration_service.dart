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
/// - v2: campos `int` de las copias en la nube (`backupKeepLast`, `backupEvery`,
///   `backupHour`, `backupMinute`, `backupConsecutiveFailures`). Al añadir un
///   `int` no-nullable a una colección con filas ya guardadas, Isar rellena esas
///   filas con su centinela `-9223372036854775808` (Int.MIN) en vez del default
///   del constructor Dart. El registro `settings` preexistente salió así, y la
///   UI mostraba "conservar las últimas -9223372036854775808 copias". Se sanean.
const int kCurrentDataVersion = 2;

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

    if (settings.dataVersion < 2) {
      _sanitizeBackupFields(settings);
    }

    if (settings.dataVersion != kCurrentDataVersion) {
      settings.dataVersion = kCurrentDataVersion;
      await isar.settings.put(settings);
    }
  });
}

/// v2: devuelve a un valor válido los `int` de las copias en la nube que Isar
/// haya dejado en su centinela (Int.MIN) en el registro `settings` preexistente.
/// Solo toca lo que está fuera de rango, así que es idempotente y no pisa una
/// configuración que el usuario sí hubiera puesto (los strings/bools con las
/// credenciales no se tocan).
void _sanitizeBackupFields(AppSettings s) {
  if (s.backupKeepLast < 1 || s.backupKeepLast > 999) s.backupKeepLast = 10;
  if (s.backupEvery < 1 || s.backupEvery > 999) s.backupEvery = 1;
  if (s.backupHour < 0 || s.backupHour > 23) s.backupHour = 3;
  if (s.backupMinute < 0 || s.backupMinute > 59) s.backupMinute = 0;
  if (s.backupConsecutiveFailures < 0) s.backupConsecutiveFailures = 0;
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
