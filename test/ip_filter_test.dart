import 'package:finanzas/features/sync/net/sync_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('preferLanAddresses', () {
    test('con 192.168 presente descarta la 10.x y la link-local', () {
      final result = preferLanAddresses([
        '10.0.0.2',
        '192.168.1.5',
        '169.254.10.10',
      ]);
      expect(result, ['192.168.1.5']);
    });

    test('si solo hay 10.x, la muestra (no hardcodea 192)', () {
      expect(preferLanAddresses(['10.1.2.3', '169.254.0.1']), ['10.1.2.3']);
    });

    test('mantiene todas las del mejor rango si hay varias', () {
      final result = preferLanAddresses([
        '192.168.1.5',
        '192.168.0.7',
        '10.0.0.2',
      ]);
      expect(result, containsAll(['192.168.1.5', '192.168.0.7']));
      expect(result, isNot(contains('10.0.0.2')));
    });

    test('172.16/12 gana a 10/8 pero pierde con 192.168', () {
      expect(preferLanAddresses(['10.0.0.2', '172.16.5.4']), ['172.16.5.4']);
      expect(preferLanAddresses(['172.20.5.4', '192.168.1.5']),
          ['192.168.1.5']);
      // 172.15 y 172.32 NO son privadas → se tratan como "resto".
      expect(preferLanAddresses(['172.15.0.1', '10.0.0.2']), ['10.0.0.2']);
    });

    test('descarta link-local aunque sea lo único', () {
      expect(preferLanAddresses(['169.254.1.1']), isEmpty);
      expect(preferLanAddresses(const []), isEmpty);
    });
  });
}
