/// Payload del QR que muestra el admin (ver `_PairingInfo` en `sync_screen.dart`):
/// `finanzas-sync:host=IP;port=N;pin=NNNNNN`.
class SyncQrPayload {
  const SyncQrPayload(
      {required this.host, required this.port, required this.pin});

  final String host;
  final int port;
  final String pin;
}

const _prefix = 'finanzas-sync:';

/// Parsea el payload; devuelve `null` si no tiene el prefijo esperado o le
/// falta algún campo obligatorio (host, pin) o el puerto no es numérico.
SyncQrPayload? parseSyncQrPayload(String raw) {
  if (!raw.startsWith(_prefix)) return null;

  final params = <String, String>{};
  for (final part in raw.substring(_prefix.length).split(';')) {
    final i = part.indexOf('=');
    if (i <= 0) continue;
    params[part.substring(0, i)] = part.substring(i + 1);
  }

  final host = params['host'];
  final pin = params['pin'];
  if (host == null || host.isEmpty || pin == null || pin.isEmpty) return null;

  final port = int.tryParse(params['port'] ?? '');
  if (port == null) return null;

  return SyncQrPayload(host: host, port: port, pin: pin);
}
