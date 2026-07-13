import 'package:finanzas/features/wallet/known_supermarkets.dart';
import 'package:finanzas/features/wallet/wallet_notification_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 7, 13, 12, 30);

  ParsedWalletTxn? parse(String title, String text) => parseWalletNotification(
        package: 'com.google.android.apps.walletnfcrel',
        title: title,
        text: text,
        postedAt: now,
      );

  group('parseWalletNotification', () {
    test('pago en español: importe con coma y "en COMERCIO"', () {
      final r = parse('Google Wallet', 'Has pagado 12,34 € en Mercadona con tu tarjeta');
      expect(r, isNotNull);
      expect(r!.cents, 1234);
      expect(r.merchant, 'Mercadona');
      expect(r.date, now);
    });

    test('comercio en el título cuando el cuerpo no lo nombra', () {
      final r = parse('LIDL', '23,50 €');
      expect(r!.cents, 2350);
      expect(r.merchant, 'LIDL');
    });

    test('formato anglosajón con símbolo delante', () {
      final r = parse('Google Wallet', 'You paid \$8.99 at Starbucks');
      expect(r!.cents, 899);
      expect(r.merchant, 'Starbucks');
    });

    test('miles con punto y decimales con coma', () {
      final r = parse('El Corte Inglés', 'Pago de 1.234,56 € en El Corte Inglés');
      expect(r!.cents, 123456);
      expect(r.merchant, 'El Corte Inglés');
    });

    test('importe entero sin decimales junto al símbolo', () {
      final r = parse('Repsol', 'Pago de 40 € en Repsol');
      expect(r!.cents, 4000);
      expect(r.merchant, 'Repsol');
    });

    test('no es un pago: sin importe → null', () {
      expect(parse('Google Wallet', 'Se ha añadido una tarjeta a tu Wallet'), isNull);
    });

    test('título genérico y sin "en X" deja el comercio vacío', () {
      final r = parse('Google Wallet', 'Pago realizado por 5,00 €');
      expect(r!.cents, 500);
      expect(r.merchant, isEmpty);
    });
  });

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
