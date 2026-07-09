import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Servicio en primer plano que mantiene vivo el servidor de sincronización
/// (el `HttpServer` corre en el isolate principal de la app) cuando la pantalla
/// se apaga o la app pasa a segundo plano. Su único fin es evitar que Android
/// mate el proceso: el task handler no hace trabajo, el servidor sigue en el
/// isolate principal.
///
/// Limitación: con la app **cerrada del todo** (deslizada de recientes) el
/// sistema puede detener el servicio según el fabricante. Cubre el caso real de
/// pantalla apagada / app en segundo plano.
const _channelId = 'finanzas_sync_server';
const _title = 'Servidor de sincronización activo';

/// Inicializa el plugin (idempotente). Se llama antes de arrancar el servicio.
void initSyncForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: _channelId,
      channelName: 'Servidor de sincronización',
      channelDescription:
          'Mantiene el servidor de sincronización activo en segundo plano.',
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
}

/// Arranca (o actualiza) el servicio en primer plano con una notificación
/// persistente que muestra la dirección del servidor. Mejor esfuerzo: cualquier
/// error se ignora para no romper el arranque del servidor.
Future<void> startSyncForegroundService({required String address}) async {
  try {
    initSyncForegroundTask();
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: _title,
        notificationText: address,
      );
      return;
    }
    await FlutterForegroundTask.startService(
      notificationTitle: _title,
      notificationText: address,
      callback: startSyncForegroundCallback,
    );
  } catch (_) {
    // best-effort
  }
}

/// Detiene el servicio en primer plano si está activo. Mejor esfuerzo.
Future<void> stopSyncForegroundService() async {
  try {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  } catch (_) {
    // best-effort
  }
}

/// Punto de entrada del isolate del servicio. No hace trabajo: solo instala un
/// handler vacío (el servidor real vive en el isolate principal).
@pragma('vm:entry-point')
void startSyncForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(_SyncTaskHandler());
}

class _SyncTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}
