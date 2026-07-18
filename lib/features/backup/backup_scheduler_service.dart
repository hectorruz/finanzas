/// Orquesta las copias en la nube: decide si toca, exporta, sube, rota y deja
/// registro. Es la única pieza de la feature que toca Isar, red y notificaciones
/// a la vez; toda la lógica que se puede aislar vive en `backup_planner.dart`,
/// `backup_retention.dart` y los proveedores.
library;

import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../../core/db/isar_provider.dart';
import '../../core/notifications/local_notifications.dart';
import '../../data/backup_service.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/enums.dart';
import '../../data/repositories/recurring_repository.dart';
import '../../data/repositories/settings_repository.dart';
import 'backup_planner.dart';
import 'backup_provider_factory.dart';
import 'backup_retention.dart';
import 'cloud_backup_provider.dart';
import 'google_drive_provider.dart';

/// Resultado de un intento de copia, para que la UI muestre algo concreto.
class BackupResult {
  BackupResult.success(this.message) : ok = true;
  BackupResult.failure(this.message) : ok = false;
  final bool ok;
  final String message;
}

/// Cómo se comprueba la conectividad. Se inyecta en los tests (por defecto,
/// `connectivity_plus`).
typedef ConnectivityProbe = Future<List<ConnectivityResult>> Function();

/// Fábrica del proveedor. Se inyecta en los tests para no tocar la red real.
typedef ProviderBuilder = CloudBackupProvider Function(AppSettings settings);

class BackupSchedulerService {
  BackupSchedulerService(
    this._isar, {
    ProviderBuilder? providerBuilder,
    ConnectivityProbe? connectivityProbe,
    DateTime Function()? now,
  })  : _providerBuilder = providerBuilder ?? ((s) => providerFor(s)),
        _connectivityProbe =
            connectivityProbe ?? (() => Connectivity().checkConnectivity()),
        _now = now ?? DateTime.now;

  final Isar _isar;
  final ProviderBuilder _providerBuilder;
  final ConnectivityProbe _connectivityProbe;
  final DateTime Function() _now;

  /// Rango de ids libre: recurrentes usan ids bajos, pagos `810000000+`, sync
  /// `900000000+`. Aquí un único id fijo (solo hay una notificación de fallo).
  static const int _notifId = 800000000;

  static const _channel = AndroidNotificationDetails(
    'backup',
    'Copias de seguridad',
    channelDescription: 'Avisos de fallos en las copias en la nube',
    importance: Importance.defaultImportance,
  );

  SettingsRepository get _settings => SettingsRepository(_isar);

  /// Hace una copia **solo si toca**: comprueba activación, cadencia, backoff y
  /// Wi-Fi. Es el punto de entrada de los disparos oportunistas (arranque,
  /// reanudación, entrada en Wi-Fi), así que es silencioso y nunca lanza.
  Future<void> runIfDue() async {
    try {
      final s = await _settings.getOrCreate();
      if (!s.backupEnabled) return;
      final now = _now();

      // El ancla debería existir si la feature está activa; si falta (activada
      // en una versión previa), la fijamos ahora y copiamos.
      final anchor = s.backupAnchorAt ??
          DateTime(now.year, now.month, now.day, s.backupHour, s.backupMinute);

      final due = isBackupDue(
        anchor: anchor,
        freq: s.backupFrequencyEnum,
        every: s.backupEvery,
        lastRun: s.backupLastRunAt,
        now: now,
      );
      if (!due) return;
      if (!_backoffElapsed(s, now)) return;
      if (s.backupWifiOnly && !await _hasWifi()) return;

      await _run(s, notify: true);
    } catch (_) {
      // runIfDue no debe tumbar nunca el arranque ni la reanudación de la app.
    }
  }

  /// Copia bajo demanda (botón "Copiar ahora"). Devuelve el resultado para la
  /// UI. No mira la cadencia ni el backoff, pero sí respeta el gate de Wi-Fi.
  Future<BackupResult> runNow({bool notify = false}) async {
    final s = await _settings.getOrCreate();
    if (s.backupWifiOnly && !await _hasWifi()) {
      return BackupResult.failure(
          'No se copió: no hay Wi-Fi (puedes desactivar "solo con Wi-Fi").');
    }
    return _run(s, notify: notify);
  }

  Future<BackupResult> _run(AppSettings s, {required bool notify}) async {
    final now = _now();
    final provider = _providerBuilder(s);
    try {
      final json = await BackupService(_isar).exportJson();
      final filename = backupFilename(now);
      await provider.upload(filename, utf8.encode(json));

      // Rotación: si falla, la copia ya está subida y es válida — no se
      // invalida el éxito, pero el aviso viaja en el mensaje de estado.
      String? rotationWarning;
      try {
        final entries = await provider.list();
        for (final old in entriesToDelete(entries, s.backupKeepLast)) {
          await provider.delete(old);
        }
      } on CloudBackupException catch (e) {
        rotationWarning = 'no se pudieron borrar copias antiguas: ${e.message}';
      }

      final label = provider.label;
      final msg = rotationWarning == null
          ? 'OK · $label · $filename'
          : 'OK · $label · $filename (aviso: $rotationWarning)';

      await _settings.update((x) {
        x.backupAnchorAt ??= DateTime(
            now.year, now.month, now.day, s.backupHour, s.backupMinute);
        x.backupLastRunAt = now;
        x.backupLastAttemptAt = now;
        x.backupLastResult = msg;
        x.backupConsecutiveFailures = 0;
        _persistFolderId(x, provider);
      });
      return BackupResult.success(msg);
    } catch (e) {
      final message = e is CloudBackupException ? e.message : e.toString();
      final failures = s.backupConsecutiveFailures + 1;
      await _settings.update((x) {
        // OJO: backupLastRunAt NO se toca. Solo el intento avanza, para que el
        // backoff cuente sin dar la copia por hecha.
        x.backupLastAttemptAt = now;
        x.backupLastResult = 'Error · ${provider.label} · $message';
        x.backupConsecutiveFailures = failures;
      });
      // El primer fallo puede ser un corte de red pasajero; avisamos a partir
      // del segundo para no ser cansinos.
      if (notify && failures >= 2) {
        await _notifyFailure(provider.label, message);
      }
      return BackupResult.failure(message);
    } finally {
      provider.close();
    }
  }

  /// Lista las copias del destino activo, para la pantalla de restaurar.
  Future<List<BackupEntry>> listRemote() async {
    final s = await _settings.getOrCreate();
    final provider = _providerBuilder(s);
    try {
      final entries = await provider.list();
      entries.retainWhere((e) => isBackupFilename(e.name));
      entries.sort((a, b) => b.name.compareTo(a.name)); // más reciente primero
      return entries;
    } finally {
      provider.close();
    }
  }

  /// Descarga [entry] y **reemplaza** todos los datos por los de esa copia.
  /// Rematerializa las recurrentes, como hace la importación manual.
  Future<void> restoreFrom(BackupEntry entry) async {
    final s = await _settings.getOrCreate();
    final provider = _providerBuilder(s);
    try {
      final bytes = await provider.download(entry);
      await BackupService(_isar).importJson(utf8.decode(bytes));
      await RecurringRepository(_isar).materializeDue();
    } finally {
      provider.close();
    }
  }

  /// Prueba las credenciales del destino [provider] sin subir una copia.
  Future<BackupResult> testConnection(AppSettings s,
      {BackupProvider? provider}) async {
    final p = _providerBuilder(_withProvider(s, provider));
    try {
      await p.testConnection();
      return BackupResult.success('Conexión correcta con ${p.label}.');
    } catch (e) {
      final message = e is CloudBackupException ? e.message : e.toString();
      return BackupResult.failure(message);
    } finally {
      p.close();
    }
  }

  AppSettings _withProvider(AppSettings s, BackupProvider? provider) {
    if (provider == null) return s;
    return s..backupProvider = provider.name;
  }

  /// Cachea el id de carpeta que Drive haya resuelto, para no rebuscarlo.
  void _persistFolderId(AppSettings x, CloudBackupProvider provider) {
    if (provider is! GoogleDriveBackupProvider) return;
    final id = provider.resolvedFolderId;
    if (id == null || id.isEmpty) return;
    final config = x.configFor(BackupProvider.googleDrive);
    if (config.folderId == id) return;
    x.backupProviderConfigs =
        x.withBackupConfig(config.copyWith(folderId: id));
  }

  bool _backoffElapsed(AppSettings s, DateTime now) {
    if (s.backupConsecutiveFailures == 0) return true;
    final last = s.backupLastAttemptAt;
    if (last == null) return true;
    // 2^fallos horas, tope 24h: 1º→2h, 2º→4h, 3º→8h … a partir de ~5 fallos, 24h.
    final hours = s.backupConsecutiveFailures >= 5
        ? 24
        : (1 << s.backupConsecutiveFailures);
    final wait = Duration(hours: hours > 24 ? 24 : hours);
    return now.isAfter(last.add(wait));
  }

  Future<bool> _hasWifi() async {
    try {
      final results = await _connectivityProbe();
      return results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet);
    } catch (_) {
      // Si no sabemos el estado de la red, no bloqueamos la copia.
      return true;
    }
  }

  Future<void> _notifyFailure(String label, String message) async {
    if (!await ensureNotificationsInitialized()) return;
    await localNotificationsPlugin.show(
      id: _notifId,
      title: 'La copia de seguridad falló',
      body: '$label: $message',
      notificationDetails: const NotificationDetails(android: _channel),
      payload: 'backup',
    );
  }
}

final backupSchedulerServiceProvider = Provider<BackupSchedulerService>(
  (ref) => BackupSchedulerService(ref.watch(isarProvider)),
);
