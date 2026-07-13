import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:isar_community/isar.dart';

import '../../core/notifications/local_notifications.dart';
import '../../data/backup_service.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/enums.dart';
import '../../data/repositories/settings_repository.dart';
import 'backup_planner.dart';
import 'backup_target.dart';
import 'google_drive_target.dart';
import 'local_file_target.dart';
import 'nextcloud_target.dart';

/// Resultado de una copia (para la UI cuando se lanza "Hacer copia ahora").
class BackupResult {
  const BackupResult({required this.ok, required this.message, this.filename});
  final bool ok;
  final String message;
  final String? filename;
}

/// Orquesta las copias de seguridad automáticas: decide si toca una copia
/// (planificador puro), serializa la BD (reutiliza [BackupService.exportJson])
/// y la entrega al [BackupTarget] configurado. No abre red ni plugins salvo la
/// notificación de resultado. Se construye con la instancia cruda de Isar tanto
/// desde `main()`/`app.dart` como desde el worker de WorkManager.
class BackupSchedulerService {
  BackupSchedulerService(this._isar);
  final Isar _isar;

  /// Id de la notificación de resultado (base propia, disjunta de recurrentes y
  /// del recordatorio de sync `900000000+`).
  static const _notifId = 800000000;

  static const _channel = AndroidNotificationDetails(
    'backup',
    'Copias de seguridad',
    channelDescription: 'Resultado de las copias de seguridad automáticas',
    importance: Importance.low,
  );

  SettingsRepository get _settings => SettingsRepository(_isar);

  /// Hace una copia **solo si toca** (arranque de la app, reanudar, o el worker
  /// periódico). No hace nada si las copias están desactivadas.
  Future<void> runIfDue() async {
    final s = await _settings.getOrCreate();
    if (!s.backupEnabled) return;
    final due = isBackupDue(
      freq: s.backupFrequencyEnum,
      lastRun: s.backupLastRunAt,
      now: DateTime.now(),
    );
    if (!due) return;
    await runNow(notify: true);
  }

  /// Hace una copia **ahora** al destino configurado. Actualiza
  /// `backupLastRunAt`/`backupLastResult` y devuelve el resultado. Con [notify]
  /// muestra una notificación de éxito/fallo (para las copias en segundo plano).
  Future<BackupResult> runNow({bool notify = false}) async {
    final s = await _settings.getOrCreate();
    final target = _targetFor(s);
    final filename = _filename();
    try {
      final json = await BackupService(_isar).exportJson();
      final bytes = utf8.encode(json);
      await target.upload(filename, bytes);
      final now = DateTime.now();
      await _settings.update((x) {
        x.backupLastRunAt = now;
        x.backupLastResult = 'OK · ${target.label} · $filename';
      });
      if (notify) {
        await _notify('Copia de seguridad realizada',
            '${target.label}: $filename');
      }
      return BackupResult(ok: true, message: 'Copia realizada', filename: filename);
    } catch (e) {
      await _settings.update((x) => x.backupLastResult = 'Error: $e');
      if (notify) await _notify('Fallo en la copia de seguridad', '$e');
      return BackupResult(ok: false, message: '$e');
    }
  }

  /// Construye el destino según los ajustes.
  BackupTarget _targetFor(AppSettings s) {
    switch (s.backupDestinationEnum) {
      case BackupDestination.localFile:
        return LocalFileBackupTarget(keepLast: s.backupKeepLast);
      case BackupDestination.nextcloud:
        return NextcloudBackupTarget(
          baseUrl: s.nextcloudBaseUrl,
          user: s.nextcloudUser,
          password: s.nextcloudPassword,
          folder: s.nextcloudFolder,
          keepLast: s.backupKeepLast,
        );
      case BackupDestination.googleDrive:
        return GoogleDriveBackupTarget(keepLast: s.backupKeepLast);
    }
  }

  String _filename() {
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    return 'finanzas_backup_$stamp.json';
  }

  Future<void> _notify(String title, String body) async {
    if (!await ensureNotificationsInitialized()) return;
    await localNotificationsPlugin.show(
      id: _notifId,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: _channel),
      payload: 'backup',
    );
  }
}
