import 'dart:convert';
import 'dart:io';

import 'package:finanzas/data/models/enums.dart';
import 'package:finanzas/data/repositories/settings_repository.dart';
import 'package:finanzas/features/backup/backup_scheduler_service.dart';
import 'package:finanzas/features/backup/local_file_target.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/test_isar.dart';

/// Fake de path_provider apuntando a un directorio temporal, para que el destino
/// de copia local (`getApplicationDocumentsDirectory`) funcione en test.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this._dir);
  final Directory _dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => _dir.path;

  @override
  Future<String?> getTemporaryPath() async => _dir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initTestIsarCore);

  late Isar isar;
  late Directory tempDir;

  setUp(() async {
    isar = await openTestIsar();
    tempDir = await Directory.systemTemp.createTemp('finanzas_backup_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('runNow con destino local escribe un JSON válido y actualiza el estado',
      () async {
    final settings = SettingsRepository(isar);
    await settings.update((s) {
      s.backupEnabled = true;
      s.backupDestination = BackupDestination.localFile.name;
    });

    final result = await BackupSchedulerService(isar).runNow();
    expect(result.ok, isTrue);
    expect(result.filename, isNotNull);

    final files = await LocalFileBackupTarget.listBackups();
    expect(files, hasLength(1));
    final data =
        jsonDecode(await files.first.readAsString()) as Map<String, dynamic>;
    expect(data['version'], isNotNull);
    expect(data.containsKey('transactions'), isTrue);

    final saved = await settings.getOrCreate();
    expect(saved.backupLastRunAt, isNotNull);
    expect(saved.backupLastResult, contains('OK'));
  });

  test('runIfDue no hace nada si las copias están desactivadas', () async {
    await BackupSchedulerService(isar).runIfDue(); // backupEnabled = false
    final files = await LocalFileBackupTarget.listBackups();
    expect(files, isEmpty);
  });

  test('la rotación conserva solo las últimas backupKeepLast copias', () async {
    await SettingsRepository(isar).update((s) {
      s.backupEnabled = true;
      s.backupDestination = BackupDestination.localFile.name;
      s.backupKeepLast = 3;
    });
    final service = BackupSchedulerService(isar);
    for (var i = 0; i < 5; i++) {
      // Nombre con timestamp: forzamos orden distinto esperando 2 ms.
      await service.runNow();
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    final files = await LocalFileBackupTarget.listBackups();
    expect(files.length, lessThanOrEqualTo(3));
  });
}
