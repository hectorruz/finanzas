import 'package:finanzas/features/accounts/deposit_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('estimatedGrossInterestCents', () {
    test('interés simple sobre un año exacto', () {
      // 10.000 € al 3,75 % durante 365 días ≈ 375 €.
      final interest = estimatedGrossInterestCents(
        principalCents: 1000000,
        rateBps: 375,
        start: DateTime(2026, 1, 1),
        end: DateTime(2027, 1, 1), // 365 días
      );
      expect(interest, 37500);
    });

    test('medio año ≈ la mitad', () {
      final interest = estimatedGrossInterestCents(
        principalCents: 1000000,
        rateBps: 400,
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 1).add(const Duration(days: 182)),
      );
      // 10.000 € · 4 % · 182/365 ≈ 199,45 €.
      expect(interest, (1000000 * 400 * 182 / (10000 * 365)).round());
    });

    test('datos incompletos o rango no positivo → 0', () {
      expect(
        estimatedGrossInterestCents(
            principalCents: 1000000, rateBps: null, start: null, end: null),
        0,
      );
      expect(
        estimatedGrossInterestCents(
          principalCents: 1000000,
          rateBps: 300,
          start: DateTime(2026, 6, 1),
          end: DateTime(2026, 1, 1), // fin antes del inicio
        ),
        0,
      );
      expect(
        estimatedGrossInterestCents(
          principalCents: 0,
          rateBps: 300,
          start: DateTime(2026, 1, 1),
          end: DateTime(2027, 1, 1),
        ),
        0,
      );
    });
  });

  group('formatRateBps', () {
    test('recorta decimales innecesarios', () {
      expect(formatRateBps(375), '3,75 %');
      expect(formatRateBps(350), '3,5 %');
      expect(formatRateBps(300), '3 %');
      expect(formatRateBps(null), '—');
    });
  });

  group('daysUntilMaturity', () {
    test('positivo antes, negativo después, null sin fecha', () {
      final now = DateTime(2026, 1, 1);
      expect(daysUntilMaturity(DateTime(2026, 1, 11), now: now), 10);
      expect(daysUntilMaturity(DateTime(2025, 12, 22), now: now), -10);
      expect(daysUntilMaturity(null, now: now), isNull);
    });
  });
}
