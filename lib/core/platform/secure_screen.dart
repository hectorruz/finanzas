import 'package:flutter/services.dart';

/// Puente con `MainActivity` (Android) para activar/desactivar `FLAG_SECURE` en
/// la ventana. Con el flag puesto, el sistema **oculta la miniatura de la app en
/// la vista de tareas/recientes** y **bloquea las capturas de pantalla** — el
/// comportamiento de privacidad de las apps de banca.
///
/// Tolerante a `MissingPluginException`/`PlatformException` (tests, iOS, o
/// plataformas sin el canal): degrada a no-op en vez de lanzar, como
/// `payment_notifications.dart`/`quick_tile.dart`.
class SecureScreen {
  static const _channel = MethodChannel('com.example.finanzas/secure_screen');

  static Future<void> setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setEnabled', enabled);
    } on PlatformException {
      // ignorado
    } on MissingPluginException {
      // ignorado
    }
  }
}
