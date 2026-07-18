import 'package:finanzas/core/db/migration_service.dart';
import 'package:finanzas/data/models/app_settings.dart';
import 'package:isar_community/isar.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_isar.dart';

/// Verifica el saneo v2 de los campos `int` de las copias en la nube: al añadir
/// un `int` no-nullable a una colección con filas ya guardadas, Isar rellena
/// esas filas con su centinela Int.MIN, y la UI llegaba a mostrar "conservar las
/// últimas -9223372036854775808 copias".
void main() {
  setUpAll(initTestIsarCore);

  late Isar isar;
  setUp(() async => isar = await openTestIsar());
  tearDown(() async => isar.close(deleteFromDisk: true));

  // El valor con el que Isar rellena un `int` ausente en una fila antigua.
  const isarIntSentinel = -9223372036854775808;

  test('sanea los campos int de backup dejados en Int.MIN', () async {
    await isar.writeTxn(() async {
      await isar.settings.put(AppSettings()
        ..id = 0
        ..dataVersion = 1 // ya pasó la migración v1
        ..backupKeepLast = isarIntSentinel
        ..backupEvery = isarIntSentinel
        ..backupHour = isarIntSentinel
        ..backupMinute = isarIntSentinel
        ..backupConsecutiveFailures = isarIntSentinel
        // Configuración real que NO se debe pisar.
        ..backupEnabled = true
        ..backupProviderConfigs = [
          '{"provider":"nextcloud","password":"secreto"}'
        ]);
    });

    await runMigrations(isar);

    final s = await isar.settings.get(0);
    expect(s!.backupKeepLast, 10);
    expect(s.backupEvery, 1);
    expect(s.backupHour, 3);
    expect(s.backupMinute, 0);
    expect(s.backupConsecutiveFailures, 0);
    // Las credenciales y el interruptor siguen intactos.
    expect(s.backupEnabled, isTrue);
    expect(s.backupProviderConfigs,
        ['{"provider":"nextcloud","password":"secreto"}']);
    expect(s.dataVersion, kCurrentDataVersion);
  });

  test('no toca valores de backup ya válidos', () async {
    await isar.writeTxn(() async {
      await isar.settings.put(AppSettings()
        ..id = 0
        ..dataVersion = 1
        ..backupKeepLast = 25
        ..backupEvery = 3
        ..backupHour = 22);
    });

    await runMigrations(isar);

    final s = await isar.settings.get(0);
    expect(s!.backupKeepLast, 25);
    expect(s.backupEvery, 3);
    expect(s.backupHour, 22);
  });

  test('es idempotente', () async {
    await isar.writeTxn(() async {
      await isar.settings.put(AppSettings()
        ..id = 0
        ..dataVersion = 1
        ..backupKeepLast = isarIntSentinel);
    });

    await runMigrations(isar);
    await runMigrations(isar);

    final s = await isar.settings.get(0);
    expect(s!.backupKeepLast, 10);
    expect(s.dataVersion, kCurrentDataVersion);
  });
}
