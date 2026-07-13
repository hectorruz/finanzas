import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:isar_community/isar.dart';

import 'app.dart';
import 'core/db/isar_provider.dart';
import 'core/db/isar_service.dart';
import 'data/models/enums.dart';
import 'data/repositories/recurring_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/seed_service.dart';
import 'core/platform/wallet_notifications.dart';
import 'features/backup/backup_scheduler_service.dart';
import 'features/backup/backup_worker.dart';
import 'features/notifications/notification_service.dart';
import 'features/quick_add/quick_add_popup.dart';
import 'features/sync/sync_reminder_service.dart';
import 'features/wallet/wallet_ingest_service.dart';

/// Entrypoint del popup de alta rápida lanzado por el tile de Ajustes rápidos
/// (Android `QuickAddActivity`). Abre solo un diálogo translúcido para añadir
/// un ingreso/gasto, sin montar la app completa ni el bloqueo.
@pragma('vm:entry-point')
Future<void> quickAddMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_ES', null);
  final isar = await IsarService.open();
  runApp(
    ProviderScope(
      overrides: [
        isarProvider.overrideWithValue(isar),
      ],
      child: const QuickAddPopupApp(),
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-edge explícito: en Android con Flutter ≥3.24 y compileSdk alto el
  // modo edge-to-edge es obligatorio (la app dibuja bajo las barras del
  // sistema). Lo fijamos de forma determinista y dejamos la barra de navegación
  // transparente; cada pantalla/hoja añade el padding del inset inferior para
  // que los botones no queden tapados por la barra de 3 botones.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));

  // Datos de localización para DateFormat en español.
  await initializeDateFormatting('es_ES', null);

  // Inicialización asíncrona de Isar ANTES de runApp (directiva de calidad #4):
  // así inyectamos la instancia real en el grafo de Riverpod mediante overrides
  // y evitamos cualquier `late Isar` global.
  final isar = await IsarService.open();

  // Datos por defecto la primera vez y materialización de recurrentes pendientes.
  await SeedService(isar).seedIfEmpty();
  await RecurringRepository(isar).materializeDue();

  // Reprogramar avisos (recurrentes + recordatorio de sync) sin bloquear el
  // arranque. Ambos comparten el plugin de notificaciones (ver
  // `local_notifications.dart`); la primera llamada síncrona a
  // `ensureNotificationsInitialized()` gana y la otra espera el mismo future,
  // así que no hay doble inicialización aunque ninguna de las dos se espere.
  unawaited(RecurringNotificationService(isar).rescheduleAll());
  unawaited(SyncReminderService(SettingsRepository(isar)).reschedule());

  // Copias de seguridad automáticas: registrar/cancelar la tarea periódica de
  // segundo plano (WorkManager) según los ajustes y, como red de seguridad,
  // hacer una copia si ya tocaba (igual que `materializeDue` con las
  // recurrentes). Sin bloquear el arranque.
  unawaited(_setUpBackups(isar));

  // Lectura de notificaciones de Google Wallet: sincroniza al servicio nativo
  // las apps de origen y procesa lo capturado con la app cerrada. Sin bloquear.
  unawaited(_setUpWallet(isar));

  runApp(
    ProviderScope(
      overrides: [
        isarProvider.overrideWithValue(isar),
      ],
      child: const FinanzasApp(),
    ),
  );
}

/// Deja el segundo plano de las copias en sintonía con los ajustes y lanza una
/// copia si ya tocaba. El worker de WorkManager abre su propio Isar; aquí solo
/// registramos/cancelamos la tarea y ejecutamos la red de seguridad al arrancar.
Future<void> _setUpBackups(Isar isar) async {
  try {
    await initBackupWorkmanager();
    final s = await SettingsRepository(isar).getOrCreate();
    if (s.backupEnabled) {
      await registerBackupTask(
        requiresNetwork:
            s.backupDestinationEnum != BackupDestination.localFile,
      );
      await BackupSchedulerService(isar).runIfDue();
    } else {
      await cancelBackupTask();
    }
  } catch (_) {
    // WorkManager no disponible (p. ej. plataforma sin plugin): las copias
    // seguirán intentándose como red de seguridad al abrir/reanudar la app.
  }
}

/// Pone al día el filtro de apps de origen del servicio nativo de Wallet y
/// procesa las notificaciones capturadas mientras la app estaba cerrada.
Future<void> _setUpWallet(Isar isar) async {
  try {
    final s = await SettingsRepository(isar).getOrCreate();
    if (!s.walletReaderEnabled) return;
    await WalletNotifications.setSourcePackages(s.walletSourcePackages);
    await WalletIngestService(isar).drainAndProcess();
  } catch (_) {
    // Plataforma sin el canal (no-Android/tests): se ignora.
  }
}
