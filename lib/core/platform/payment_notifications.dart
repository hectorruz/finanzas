import 'dart:convert';

import 'package:flutter/services.dart';

/// Una notificación capturada por el servicio nativo (título/texto/paquete y
/// cuándo se publicó), tal cual, sin interpretar.
class CapturedNotification {
  const CapturedNotification({
    required this.package,
    required this.title,
    required this.text,
    required this.postedAt,
  });

  final String package;
  final String title;
  final String text;
  final DateTime postedAt;
}

/// Puente con el `PaymentNotificationListenerService` nativo (Android).
/// Tolerante a `MissingPluginException` (tests / plataformas sin el canal):
/// degrada a "sin permiso" / buffer vacío en vez de lanzar. Ver `MainActivity.kt`.
class PaymentNotifications {
  static const _channel = MethodChannel('com.example.finanzas/payments');

  /// ¿El usuario ha concedido "acceso a las notificaciones" a la app?
  static Future<bool> isPermissionGranted() async {
    try {
      return await _channel.invokeMethod<bool>('isPermissionGranted') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Abre la pantalla del sistema para conceder el acceso a notificaciones.
  static Future<void> openListenerSettings() async {
    try {
      await _channel.invokeMethod<void>('openListenerSettings');
    } on PlatformException {
      // ignorado
    } on MissingPluginException {
      // ignorado
    }
  }

  /// Fija las apps de origen cuyas notificaciones se capturan.
  static Future<void> setSourcePackages(List<String> packages) async {
    try {
      await _channel.invokeMethod<void>('setSourcePackages', packages);
    } on PlatformException {
      // ignorado
    } on MissingPluginException {
      // ignorado
    }
  }

  /// Espeja en el servicio nativo si el lector está activo. `AppSettings` vive
  /// en Isar, que el servicio no puede leer con la app cerrada: este flag es el
  /// único gate que decide si un pago arranca el engine de ingesta. Ver
  /// `syncPaymentReaderToNative`, que es quien debe llamar aquí.
  static Future<void> setReaderEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setReaderEnabled', enabled);
    } on PlatformException {
      // ignorado
    } on MissingPluginException {
      // ignorado
    }
  }

  /// Vacía y devuelve el buffer nativo de notificaciones capturadas.
  static Future<List<CapturedNotification>> drainBuffer() =>
      _readBuffer('drainBuffer');

  /// Devuelve el buffer **sin** vaciarlo (para el visor/probador de reglas).
  static Future<List<CapturedNotification>> peekBuffer() =>
      _readBuffer('peekBuffer');

  static Future<List<CapturedNotification>> _readBuffer(String method) async {
    try {
      final raw = await _channel.invokeMethod<String>(method);
      if (raw == null || raw.isEmpty) return const [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) {
        final m = e as Map<String, dynamic>;
        return CapturedNotification(
          package: m['package'] as String? ?? '',
          title: m['title'] as String? ?? '',
          text: m['text'] as String? ?? '',
          postedAt: DateTime.fromMillisecondsSinceEpoch(
              (m['postedAt'] as num?)?.toInt() ?? 0),
        );
      }).toList();
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }
}
