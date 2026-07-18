import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:finanzas/data/models/app_settings.dart';
import 'package:finanzas/data/models/enums.dart';
import 'package:finanzas/data/repositories/settings_repository.dart';
import 'package:finanzas/features/backup/backup_retention.dart';
import 'package:finanzas/features/backup/backup_scheduler_service.dart';
import 'package:finanzas/features/backup/cloud_backup_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

import 'support/test_isar.dart';

/// Proveedor en memoria, escrito a mano (el repo no usa librerías de mocks).
class _MemoryProvider implements CloudBackupProvider {
  _MemoryProvider({this.failUpload = false, this.failRotation = false});

  bool failUpload;
  bool failRotation;
  final Map<String, List<int>> store = {};
  int uploads = 0;

  @override
  String get label => 'Memoria';

  @override
  Future<void> upload(String filename, List<int> bytes) async {
    uploads++;
    if (failUpload) {
      throw CloudBackupException('sin conexión de mentira');
    }
    store[filename] = bytes;
  }

  @override
  Future<List<BackupEntry>> list() async {
    if (failRotation) {
      throw CloudBackupException('no se pudo listar');
    }
    return store.keys.map((k) => BackupEntry(id: k, name: k)).toList();
  }

  @override
  Future<List<int>> download(BackupEntry entry) async => store[entry.id]!;

  @override
  Future<void> delete(BackupEntry entry) async {
    store.remove(entry.id);
  }

  @override
  Future<void> testConnection() async {}

  @override
  void close() {}
}

void main() {
  setUpAll(initTestIsarCore);

  late Isar isar;
  late SettingsRepository settings;

  setUp(() async {
    isar = await openTestIsar();
    settings = SettingsRepository(isar);
  });
  tearDown(() async => isar.close(deleteFromDisk: true));

  BackupSchedulerService serviceWith(
    _MemoryProvider provider, {
    DateTime? now,
    List<ConnectivityResult> connectivity = const [ConnectivityResult.wifi],
  }) =>
      BackupSchedulerService(
        isar,
        providerBuilder: (_) => provider,
        connectivityProbe: () async => connectivity,
        now: () => now ?? DateTime(2026, 7, 17, 10),
      );

  Future<void> enable({
    BackupFrequency freq = BackupFrequency.daily,
    int keepLast = 10,
    bool wifiOnly = true,
    DateTime? lastRun,
    DateTime? anchor,
  }) async {
    await settings.update((s) {
      s.backupEnabled = true;
      s.backupFrequency = freq.name;
      s.backupKeepLast = keepLast;
      s.backupWifiOnly = wifiOnly;
      s.backupAnchorAt = anchor ?? DateTime(2026, 7, 1, 3);
      s.backupLastRunAt = lastRun;
    });
  }

  group('runIfDue', () {
    test('no hace nada si la feature está desactivada', () async {
      final p = _MemoryProvider();
      await serviceWith(p).runIfDue();
      expect(p.uploads, 0);
    });

    test('copia y guarda el estado cuando toca', () async {
      await enable(lastRun: DateTime(2026, 7, 16, 3));
      final p = _MemoryProvider();
      await serviceWith(p).runIfDue();
      expect(p.store.length, 1);
      final s = await settings.getOrCreate();
      expect(s.backupLastRunAt, isNotNull);
      expect(s.backupLastResult, startsWith('OK'));
      expect(s.backupConsecutiveFailures, 0);
    });

    test('no copia si aún no toca (copia de hoy, cadencia diaria)', () async {
      await enable(lastRun: DateTime(2026, 7, 17, 3));
      final p = _MemoryProvider();
      await serviceWith(p, now: DateTime(2026, 7, 17, 10)).runIfDue();
      expect(p.uploads, 0);
    });

    test('respeta "solo Wi-Fi": con datos móviles no copia', () async {
      await enable(lastRun: DateTime(2026, 7, 16, 3));
      final p = _MemoryProvider();
      await serviceWith(p, connectivity: [ConnectivityResult.mobile])
          .runIfDue();
      expect(p.uploads, 0);
    });
  });

  group('fallo y backoff', () {
    test('un fallo registra el error SIN tocar backupLastRunAt', () async {
      final lastRun = DateTime(2026, 7, 16, 3);
      await enable(lastRun: lastRun);
      final p = _MemoryProvider(failUpload: true);
      await serviceWith(p).runIfDue();
      final s = await settings.getOrCreate();
      expect(s.backupLastResult, startsWith('Error'));
      expect(s.backupConsecutiveFailures, 1);
      expect(s.backupLastRunAt, lastRun, reason: 'no se dio por hecha la copia');
      expect(s.backupLastAttemptAt, isNotNull);
    });

    test('backoff: dos runIfDue seguidos tras un fallo = un solo intento',
        () async {
      await enable(lastRun: DateTime(2026, 7, 16, 3));
      final p = _MemoryProvider(failUpload: true);
      final t = DateTime(2026, 7, 17, 10);
      // Primer intento: falla (1 fallo → espera 2h).
      await serviceWith(p, now: t).runIfDue();
      expect(p.uploads, 1);
      // A los 30 min: el backoff aún no ha pasado → no reintenta.
      await serviceWith(p, now: t.add(const Duration(minutes: 30))).runIfDue();
      expect(p.uploads, 1, reason: 'el backoff debe frenar el reintento');
      // A las 3h: ya puede reintentar.
      await serviceWith(p, now: t.add(const Duration(hours: 3))).runIfDue();
      expect(p.uploads, 2);
    });

    test('recuperarse de un fallo pone a cero el contador', () async {
      await enable(lastRun: DateTime(2026, 7, 16, 3));
      final p = _MemoryProvider(failUpload: true);
      final t = DateTime(2026, 7, 17, 10);
      await serviceWith(p, now: t).runIfDue();
      expect((await settings.getOrCreate()).backupConsecutiveFailures, 1);
      p.failUpload = false;
      await serviceWith(p, now: t.add(const Duration(hours: 3))).runIfDue();
      final s = await settings.getOrCreate();
      expect(s.backupConsecutiveFailures, 0);
      expect(s.backupLastRunAt, isNotNull);
    });
  });

  group('rotación', () {
    test('borra las copias que sobran', () async {
      await enable(keepLast: 2, lastRun: DateTime(2026, 7, 16, 3));
      final p = _MemoryProvider();
      // Dos copias viejas ya en el destino.
      p.store['finanzas_backup_2026-07-14T03-00-00Z.json'] = utf8.encode('{}');
      p.store['finanzas_backup_2026-07-15T03-00-00Z.json'] = utf8.encode('{}');
      await serviceWith(p).runIfDue();
      // Tras subir la de hoy hay 3; se conservan 2.
      final ours =
          p.store.keys.where(isBackupFilename).toList();
      expect(ours.length, 2);
      expect(ours, isNot(contains('finanzas_backup_2026-07-14T03-00-00Z.json')));
    });

    test('un fallo de rotación NO invalida la copia, pero deja aviso', () async {
      await enable(lastRun: DateTime(2026, 7, 16, 3));
      final p = _MemoryProvider(failRotation: true);
      await serviceWith(p).runIfDue();
      final s = await settings.getOrCreate();
      expect(s.backupLastResult, startsWith('OK'));
      expect(s.backupLastResult, contains('aviso'));
      expect(s.backupConsecutiveFailures, 0);
      expect(s.backupLastRunAt, isNotNull);
    });
  });

  group('runNow', () {
    test('copia bajo demanda aunque no toque por cadencia', () async {
      await enable(lastRun: DateTime(2026, 7, 17, 3)); // copia de hoy
      final p = _MemoryProvider();
      final r = await serviceWith(p).runNow();
      expect(r.ok, isTrue);
      expect(p.uploads, 1);
    });

    test('avisa si "solo Wi-Fi" y no hay Wi-Fi', () async {
      await enable(lastRun: DateTime(2026, 7, 17, 3));
      final p = _MemoryProvider();
      final r = await serviceWith(p, connectivity: [ConnectivityResult.mobile])
          .runNow();
      expect(r.ok, isFalse);
      expect(p.uploads, 0);
    });
  });

  group('restoreFrom', () {
    test('descarga una copia y reemplaza los datos', () async {
      await enable(lastRun: DateTime(2026, 7, 16, 3));
      final p = _MemoryProvider();
      final svc = serviceWith(p);
      await svc.runNow(); // deja una copia en el destino
      final entries = await svc.listRemote();
      expect(entries, isNotEmpty);
      // Restaurar no debe lanzar y debe rematerializar sin romper.
      await svc.restoreFrom(entries.first);
    });
  });
}
