import 'package:finanzas/features/payments/notification_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 7, 14, 12, 30);

  ParsedPayment? wallet(String title, String text) => parseWithRules(
        package: NotificationRule.walletPackage,
        title: title,
        text: text,
        postedAt: now,
        rules: const [],
      );

  group('Wallet (regla built-in por defecto)', () {
    test('pago en español: importe con coma y "en COMERCIO"', () {
      final r = wallet(
          'Google Wallet', 'Has pagado 12,34 € en Mercadona con tu tarjeta');
      expect(r, isNotNull);
      expect(r!.cents, 1234);
      expect(r.merchant, 'Mercadona');
      expect(r.date, now);
    });

    test('comercio en el título cuando el cuerpo no lo nombra', () {
      final r = wallet('LIDL', '23,50 €');
      expect(r!.cents, 2350);
      expect(r.merchant, 'LIDL');
    });

    test('formato anglosajón con símbolo delante', () {
      final r = wallet('Google Wallet', 'You paid \$8.99 at Starbucks');
      expect(r!.cents, 899);
      expect(r.merchant, 'Starbucks');
    });

    test('miles con punto y decimales con coma', () {
      final r = wallet('El Corte Inglés', 'Pago de 1.234,56 € en El Corte Inglés');
      expect(r!.cents, 123456);
      expect(r.merchant, 'El Corte Inglés');
    });

    test('importe entero sin decimales junto al símbolo', () {
      final r = wallet('Repsol', 'Pago de 40 € en Repsol');
      expect(r!.cents, 4000);
      expect(r.merchant, 'Repsol');
    });

    test('no es un pago: sin importe → null', () {
      expect(wallet('Google Wallet', 'Se ha añadido una tarjeta a tu Wallet'),
          isNull);
    });

    test('título genérico y sin "en X" deja el comercio vacío', () {
      final r = wallet('Google Wallet', 'Pago realizado por 5,00 €');
      expect(r!.cents, 500);
      expect(r.merchant, isEmpty);
    });
  });

  group('Detección de tarjeta (heurística)', () {
    test('bloque de bullets + dígitos → ••NNNN', () {
      final r = wallet('Mercadona', '12,34 € · Visa ••1234');
      expect(r!.card, '••1234');
    });

    test('palabra clave "terminada en"', () {
      final r = wallet('Repsol', 'Pago de 40 € · tarjeta terminada en 5678');
      expect(r!.card, '••5678');
    });

    test('sin tarjeta reconocible → vacío', () {
      final r = wallet('LIDL', '23,50 €');
      expect(r!.card, isEmpty);
    });
  });

  group('Reglas por app (regex por campo)', () {
    const rule = NotificationRule(
      package: 'com.miapp.pagos',
      label: 'Mi App',
      amountRegex: r'([0-9]+[.,][0-9]{2})\s*€',
      merchantRegex: r'Compra en (.+?) por',
      cardRegex: r'\((\d{4})\)',
    );

    test('extrae importe, comercio y tarjeta con la regla', () {
      final r = applyRule(
        rule,
        title: 'Movimiento',
        text: 'Compra en Bar Pepe por 9,90 € con tu tarjeta (4321)',
        postedAt: now,
      );
      expect(r, isNotNull);
      expect(r!.cents, 990);
      expect(r.merchant, 'Bar Pepe');
      expect(r.card, '4321');
    });

    test('regex de importe que no casa → no es un pago (null)', () {
      final r = applyRule(
        rule,
        title: 'Aviso',
        text: 'Tu saldo es de 100 €',
        postedAt: now,
      );
      // El amountRegex exige dos decimales; "100 €" no casa.
      expect(r, isNull);
    });

    test('parseWithRules elige la regla por paquete', () {
      final r = parseWithRules(
        package: 'com.miapp.pagos',
        title: 'Movimiento',
        text: 'Compra en Bar Pepe por 9,90 € con tu tarjeta (4321)',
        postedAt: now,
        rules: const [rule],
      );
      expect(r!.merchant, 'Bar Pepe');
      expect(r.card, '4321');
    });

    test('paquete sin regla cae a la semántica de Wallet', () {
      final r = parseWithRules(
        package: 'com.otra.app',
        title: 'Cafetería Central',
        text: '3,20 €',
        postedAt: now,
        rules: const [rule],
      );
      expect(r!.cents, 320);
      expect(r.merchant, 'Cafetería Central');
    });

    test('regex inválida degrada a la heurística genérica', () {
      const bad = NotificationRule(
        package: 'com.miapp.pagos',
        label: 'Mi App',
        amountRegex: r'([0-9', // paréntesis sin cerrar
      );
      final r = applyRule(
        bad,
        title: 'Mercadona',
        text: '7,00 €',
        postedAt: now,
      );
      expect(r!.cents, 700);
    });
  });

  group('NotificationRule serialización', () {
    test('encode → tryDecode conserva los campos', () {
      const rule = NotificationRule(
        package: 'com.miapp.pagos',
        label: 'Mi App',
        merchantFromTitle: true,
        amountRegex: r'([0-9]+,[0-9]{2})',
      );
      final decoded = NotificationRule.tryDecode(rule.encode());
      expect(decoded, isNotNull);
      expect(decoded!.package, 'com.miapp.pagos');
      expect(decoded.label, 'Mi App');
      expect(decoded.merchantFromTitle, isTrue);
      expect(decoded.amountRegex, r'([0-9]+,[0-9]{2})');
      expect(decoded.merchantRegex, isNull);
    });

    test('JSON corrupto o sin paquete → null', () {
      expect(NotificationRule.tryDecode('no es json'), isNull);
      expect(NotificationRule.tryDecode('{"label":"x"}'), isNull);
    });
  });
}
