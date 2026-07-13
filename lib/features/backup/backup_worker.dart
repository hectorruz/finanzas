import 'package:workmanager/workmanager.dart';

import '../../core/db/isar_service.dart';
import 'backup_scheduler_service.dart';

/// Nombre único de la tarea periódica (para registrar/cancelar) y etiqueta del
/// trabajo devuelta al handler.
const _backupUniqueName = 'finanzas-backup-periodic';
const _backupTaskName = 'finanzas.backup.periodic';

/// Cada cuánto despierta el worker a **comprobar** si toca copia. No es la
/// frecuencia de la copia (esa la decide el planificador según los ajustes):
/// es solo el latido con el que WorkManager revisa. 6 h es un buen compromiso
/// (mínimo del sistema: 15 min).
const _heartbeat = Duration(hours: 6);

/// Punto de entrada del isolate de segundo plano de WorkManager. Debe ser una
/// función top-level anotada `@pragma('vm:entry-point')`. Abre Isar por su
/// cuenta (Isar admite acceso multi-isolate a la misma instancia, igual que el
/// popup de alta rápida) y delega en el planificador.
@pragma('vm:entry-point')
void backupCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final isar = await IsarService.open();
      await BackupSchedulerService(isar).runIfDue();
    } catch (_) {
      // Best-effort: nunca devolvemos `false` para no entrar en un bucle de
      // reintentos; el propio planificador reintentará en el siguiente latido.
    }
    return true;
  });
}

/// Inicializa WorkManager con el dispatcher. Idempotente en la práctica; se
/// llama una vez al arrancar la app.
Future<void> initBackupWorkmanager() =>
    Workmanager().initialize(backupCallbackDispatcher);

/// Registra (o actualiza) la tarea periódica. [requiresNetwork] hace que
/// WorkManager espere a tener conexión (destinos remotos: Nextcloud/Drive).
Future<void> registerBackupTask({required bool requiresNetwork}) {
  return Workmanager().registerPeriodicTask(
    _backupUniqueName,
    _backupTaskName,
    frequency: _heartbeat,
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    constraints: Constraints(
      networkType:
          requiresNetwork ? NetworkType.connected : NetworkType.notRequired,
    ),
  );
}

/// Cancela la tarea periódica (copias desactivadas).
Future<void> cancelBackupTask() =>
    Workmanager().cancelByUniqueName(_backupUniqueName);
