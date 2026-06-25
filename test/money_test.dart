import 'package:finanzas/core/money/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money.parseToCents', () {
    test('coma decimal', () {
      expect(Money.parseToCents('12,34'), 1234);
    });

    test('punto decimal', () {
      expect(Money.parseToCents('12.34'), 1234);
    });

    test('miles con punto y decimal con coma', () {
      expect(Money.parseToCents('1.234,50'), 123450);
    });

    test('miles con coma y decimal con punto', () {
      expect(Money.parseToCents('1,234.50'), 123450);
    });

    test('entero sin decimales', () {
      expect(Money.parseToCents('5'), 500);
    });

    test('con símbolo de divisa', () {
      expect(Money.parseToCents('€ 9,99'), 999);
    });

    test('negativo', () {
      expect(Money.parseToCents('-3,50'), -350);
    });

    test('texto inválido devuelve null', () {
      expect(Money.parseToCents('abc'), isNull);
      expect(Money.parseToCents(''), isNull);
    });
  });

  group('Money aritmética', () {
    test('suma y resta sin errores de coma flotante', () {
      final a = const Money(10) + const Money(20);
      expect(a.cents, 30); // 0,10 + 0,20 = 0,30 exacto
    });

    test('fromDouble redondea al céntimo', () {
      expect(Money.fromDouble(12.345).cents, 1235);
      expect(Money.fromDouble(12.344).cents, 1234);
    });

    test('formatSigned', () {
      expect(const Money(1234).formatSigned().startsWith('+'), isTrue);
      expect(const Money(-1234).formatSigned().startsWith('-'), isTrue);
    });
  });
}
