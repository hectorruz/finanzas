import 'package:finanzas/features/payments/known_supermarkets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('canonicalSupermarket', () {
    test('reconoce Mercadona/Lidl/Dia por palabra', () {
      expect(canonicalSupermarket('Mercadona'), 'Mercadona');
      expect(canonicalSupermarket('LIDL Vilanova'), 'Lidl');
      expect(canonicalSupermarket('SUPERMERCADO DIA'), 'Dia');
      expect(canonicalSupermarket('Compra en Dia'), 'Dia');
    });

    test('no confunde "dia" como substring de otra palabra', () {
      expect(canonicalSupermarket('Media Markt'), isNull);
      expect(canonicalSupermarket('Diamond Store'), isNull);
      expect(canonicalSupermarket('Farmacia Guardia'), isNull);
    });

    test('comercio desconocido → null', () {
      expect(canonicalSupermarket('Starbucks'), isNull);
      expect(canonicalSupermarket(''), isNull);
    });
  });
}
