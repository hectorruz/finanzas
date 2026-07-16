import 'package:finanzas/features/payments/card_account_rule.dart';
import 'package:finanzas/features/payments/notification_parser.dart';
import 'package:finanzas/features/payments/regex_help.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('regexError', () {
    test('acepta un patrón válido', () {
      expect(regexError(r'([0-9]+[.,][0-9]{2})\s*€'), isNull);
    });

    test('un campo vacío es válido (= detección automática)', () {
      expect(regexError(''), isNull);
      expect(regexError('   '), isNull);
    });

    test('detecta el paréntesis sin cerrar, que el parser ignoraría en silencio',
        () {
      expect(regexError('Compra en (.+? por'), isNotNull);
    });

    test('detecta el cuantificador huérfano', () {
      expect(regexError('*importe'), isNotNull);
    });
  });

  group('recetario', () {
    for (final r in kRegexRecipes) {
      test('"${r.title}" extrae ${r.extracts} de su ejemplo', () {
        expect(regexError(r.pattern), isNull,
            reason: 'el patrón de la receta debe compilar');
        final m = RegExp(r.pattern, caseSensitive: false).firstMatch(r.example);
        expect(m, isNotNull, reason: 'debe casar con su propio ejemplo');
        // Misma semántica que el parser: grupo 1 si lo hay, si no la
        // coincidencia entera (ver `_resolveCents` y compañía).
        final raw = (m!.groupCount >= 1 ? m.group(1) : null) ?? m.group(0);
        expect(raw, r.extracts);
      });
    }

    test('cada campo tiene al menos una receta', () {
      for (final field in RegexField.values) {
        expect(kRegexRecipes.where((r) => r.field == field), isNotEmpty,
            reason: 'falta receta para $field');
      }
    });
  });

  group('las recetas funcionan de verdad en una regla', () {
    test('importe + tienda + tarjeta sobre una notificación de banco', () {
      const rule = NotificationRule(
        package: 'com.banco.app',
        label: 'Mi Banco',
        amountRegex: r'([0-9]+[.,][0-9]{2})\s*€',
        merchantRegex: r'\ben\s+(.+?)(?:\s+con\b|[.,]|$)',
        cardRegex: r'(?:\*{2,}|•{2,}|x{4})\s*(\d{4})',
      );
      final parsed = applyRule(
        rule,
        title: 'Compra realizada',
        text: 'Pago de 23,45 € en MERCADONA con tarjeta ••1234',
        postedAt: DateTime(2026, 7, 16),
      );
      expect(parsed, isNotNull);
      expect(parsed!.cents, 2345);
      expect(parsed.merchant, 'MERCADONA');
      // Con un regex propio se guarda el grupo tal cual: el prefijo `••` solo lo
      // pone la heurística automática. Da igual para casar la tarjeta con su
      // cuenta, porque `CardAccountRule.matches` compara solo los dígitos.
      expect(parsed.card, '1234');
      expect(
          const CardAccountRule(card: '••1234', accountId: 7).matches('1234'),
          isTrue);
    });
  });
}
