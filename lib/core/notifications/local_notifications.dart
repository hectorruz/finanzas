import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Instancia única del plugin, compartida por todas las features que
/// programan avisos (recurrentes, recordatorio de sync, …). Un único proceso
/// nativo de notificaciones subyace a cualquier instancia de
/// `FlutterLocalNotificationsPlugin`, así que inicializar una sola vez evita
/// que dos `initialize()` se pisen (p. ej. el callback de toque de uno
/// sobrescribiendo el del otro).
final FlutterLocalNotificationsPlugin localNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// Se invoca con el `payload` de la notificación tocada, tanto si la app ya
/// estaba en marcha como (una vez comprobado el arranque en frío, ver
/// `app.dart`) si la lanzó la propia notificación. Cada feature que necesite
/// reaccionar a un toque distingue por el prefijo/valor de su payload.
void Function(String? payload)? onNotificationTap;

Future<bool>? _initFuture;

/// Inicializa el plugin y la zona horaria una sola vez (llamadas concurrentes
/// comparten el mismo resultado en vuelo). Tolerante a fallos: si la
/// plataforma no soporta notificaciones (p. ej. tests), queda desactivado.
Future<bool> ensureNotificationsInitialized() => _initFuture ??= _doInit();

Future<bool> _doInit() async {
  try {
    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name.identifier));
    } catch (_) {
      // Nos quedamos con la zona por defecto de `tz.local`.
    }
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      linux: LinuxInitializationSettings(defaultActionName: 'Abrir'),
    );
    final ok = await localNotificationsPlugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (details) =>
          onNotificationTap?.call(details.payload),
    );
    if (ok == false) return false;
    try {
      await localNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {
      // Pedir el permiso necesita una Activity: el plugin usa `mainActivity`
      // sin comprobar null, así que en un engine sin UI (`paymentIngestMain`)
      // lanza. No es fatal —`show()` solo usa el contexto de aplicación—, pero
      // si dejamos escapar el error se cachea `_initFuture = false` y el
      // proceso entero se queda sin notificaciones.
    }
    return true;
  } catch (_) {
    return false;
  }
}
