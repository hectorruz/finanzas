import 'package:finanzas/core/planning/goal_planning.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('goalProgress', () {
    test('clampa entre 0 y 1', () {
      expect(goalProgress(50, 100), 0.5);
      expect(goalProgress(200, 100), 1.0);
      expect(goalProgress(10, 0), 0.0);
    });
  });

  group('goalRemainingCents', () {
    test('nunca negativo', () {
      expect(goalRemainingCents(30, 100), 70);
      expect(goalRemainingCents(150, 100), 0);
    });
  });

  group('goalMonthsToTarget', () {
    test('redondea hacia arriba', () {
      expect(
          goalMonthsToTarget(
              planMode: 'contribution',
              monthlyContributionCents: 1000,
              remainingCents: 2500),
          3);
    });
    test('null si no es modo contribution o aporte 0', () {
      expect(
          goalMonthsToTarget(
              planMode: 'deadline',
              monthlyContributionCents: 1000,
              remainingCents: 2500),
          isNull);
      expect(
          goalMonthsToTarget(
              planMode: 'contribution',
              monthlyContributionCents: 0,
              remainingCents: 2500),
          isNull);
    });
    test('0 si ya está conseguido', () {
      expect(
          goalMonthsToTarget(
              planMode: 'contribution',
              monthlyContributionCents: 1000,
              remainingCents: 0),
          0);
    });
  });

  group('goalProjectedDate', () {
    test('suma los meses a la fecha actual', () {
      final d = goalProjectedDate(
        planMode: 'contribution',
        monthlyContributionCents: 1000,
        remainingCents: 3000,
        now: DateTime(2026, 1, 15),
      );
      expect(d, DateTime(2026, 4, 15));
    });
  });

  group('goalRequiredMonthlyCents', () {
    test('reparte lo que falta hasta la fecha límite', () {
      final monthly = goalRequiredMonthlyCents(
        planMode: 'deadline',
        deadline: DateTime(2026, 7, 1),
        remainingCents: 6000,
        now: DateTime(2026, 1, 1),
      );
      expect(monthly, 1000); // 6 meses
    });
    test('null si la fecha ya pasó', () {
      expect(
          goalRequiredMonthlyCents(
            planMode: 'deadline',
            deadline: DateTime(2025, 1, 1),
            remainingCents: 6000,
            now: DateTime(2026, 1, 1),
          ),
          isNull);
    });
  });

  group('goalPlanLabelFor', () {
    test('anuncia objetivo conseguido', () {
      expect(
          goalPlanLabelFor(
              currentCents: 100,
              targetCents: 100,
              planMode: 'contribution',
              monthlyContributionCents: 10),
          '¡Objetivo conseguido!');
    });
  });
}
