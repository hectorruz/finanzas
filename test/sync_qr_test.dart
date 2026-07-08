import 'package:finanzas/features/sync/net/sync_qr.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parseo puro del payload del QR de emparejamiento.
void main() {
  test('parsea host, puerto y pin', () {
    final p = parseSyncQrPayload(
        'finanzas-sync:host=192.168.1.42;port=8080;pin=123456');
    expect(p, isNotNull);
    expect(p!.host, '192.168.1.42');
    expect(p.port, 8080);
    expect(p.pin, '123456');
  });

  test('prefijo distinto → null', () {
    expect(parseSyncQrPayload('otra-cosa:host=1.2.3.4;port=80;pin=1'), isNull);
  });

  test('sin pin → null', () {
    expect(parseSyncQrPayload('finanzas-sync:host=1.2.3.4;port=80'), isNull);
  });

  test('sin host → null', () {
    expect(parseSyncQrPayload('finanzas-sync:port=80;pin=123456'), isNull);
  });

  test('puerto no numérico → null', () {
    expect(parseSyncQrPayload('finanzas-sync:host=1.2.3.4;port=abc;pin=123456'),
        isNull);
  });

  test('orden de campos indiferente', () {
    final p =
        parseSyncQrPayload('finanzas-sync:pin=999999;host=10.0.0.5;port=9090');
    expect(p, isNotNull);
    expect(p!.host, '10.0.0.5');
    expect(p.port, 9090);
    expect(p.pin, '999999');
  });
}
