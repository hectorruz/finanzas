import 'package:web/web.dart' as web;

/// Persistencia del emparejamiento de la webapp en el `localStorage` del
/// navegador, para no volver a pedir IP/puerto/PIN en cada recarga. El token
/// sigue siendo el mismo que emite el móvil al emparejar; si caduca o se revoca,
/// la primera llamada a la API devuelve 401 y la app vuelve a la conexión.
class WebSession {
  static const _kHost = 'finanzas.host';
  static const _kPort = 'finanzas.port';
  static const _kToken = 'finanzas.token';
  static const _kDeviceId = 'finanzas.deviceId';
  static const _kAmoled = 'finanzas.amoled';

  static web.Storage get _store => web.window.localStorage;

  static String? get host => _store.getItem(_kHost);
  static int? get port => int.tryParse(_store.getItem(_kPort) ?? '');
  static String? get token => _store.getItem(_kToken);
  static String? get deviceId => _store.getItem(_kDeviceId);

  /// Override **local del navegador** del modo AMOLED (negro puro en oscuro).
  /// `null` = seguir el ajuste del móvil (`SettingsDto.amoled`). Es local para no
  /// pisar el tema del móvil al cambiarlo desde la web.
  static bool? get amoled {
    final v = _store.getItem(_kAmoled);
    return v == null ? null : v == 'true';
  }

  static set amoled(bool? v) {
    if (v == null) {
      _store.removeItem(_kAmoled);
    } else {
      _store.setItem(_kAmoled, '$v');
    }
  }

  static bool get hasSession =>
      (host?.isNotEmpty ?? false) && (token?.isNotEmpty ?? false);

  static void save({
    required String host,
    required int port,
    required String token,
    required String deviceId,
  }) {
    _store.setItem(_kHost, host);
    _store.setItem(_kPort, '$port');
    _store.setItem(_kToken, token);
    _store.setItem(_kDeviceId, deviceId);
  }

  static void clear() {
    _store.removeItem(_kHost);
    _store.removeItem(_kPort);
    _store.removeItem(_kToken);
    // Se conserva el deviceId: identifica de forma estable a este navegador
    // frente al móvil aunque se desconecte y vuelva a emparejar.
  }
}
