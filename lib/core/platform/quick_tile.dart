import 'package:flutter/services.dart';

/// Puente con el Quick Settings Tile nativo de Android.
///
/// El tile lanza la app con una "acción"; aquí la recogemos para que la capa
/// de UI navegue al editor de movimientos. Ver `QuickAddTileService.kt` y
/// `MainActivity.kt`.
class QuickTile {
  static const _channel = MethodChannel('com.example.finanzas/quick_tile');

  /// Acción con la que arrancó la app (arranque en frío), o `null`.
  /// Se consume una sola vez: el lado nativo la limpia tras devolverla.
  static Future<String?> getInitialAction() async {
    try {
      return await _channel.invokeMethod<String>('getInitialAction');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      // Plataforma sin el canal (p. ej. tests o no-Android).
      return null;
    }
  }

  /// Registra un handler para acciones recibidas mientras la app ya corre
  /// (el tile reenvía vía `onNewIntent`).
  static void setActionHandler(void Function(String action) onAction) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onQuickAction') {
        final action = call.arguments as String?;
        if (action != null) onAction(action);
      }
      return null;
    });
  }

  /// Acción del tile "Nuevo movimiento".
  static const newMovement = 'new_movement';
}
