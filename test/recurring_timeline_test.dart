import 'package:finanzas/data/models/enums.dart';
import 'package:finanzas/features/web/analytics/recurring_timeline.dart';
import 'package:finanzas/features/web/web_models.dart';
import 'package:flutter_test/flutter_test.dart';

RecurringDto _rule({
  required DateTime nextDate,
  RecurringFrequency freq = RecurringFrequency.monthly,
  int interval = 1,
  bool active = true,
  DateTime? endDate,
  TransactionType type = TransactionType.expense,
  int amountCents = 1000,
}) =>
    RecurringDto(
      name: 'r',
      type: type,
      amountCents: amountCents,
      frequency: freq,
      interval: interval,
      nextDate: nextDate,
      endDate: endDate,
      active: active,
      accountId: 1,
    );

void main() {
  group('occurrencesOf', () {
    test('mensual genera una por mes dentro del rango', () {
      final dates = occurrencesOf(
        _rule(nextDate: DateTime(2026, 1, 15)),
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 4, 1),
      );
      expect(dates, [
        DateTime(2026, 1, 15),
        DateTime(2026, 2, 15),
        DateTime(2026, 3, 15),
      ]);
    });

    test('respeta la fecha de fin', () {
      final dates = occurrencesOf(
        _rule(nextDate: DateTime(2026, 1, 1), endDate: DateTime(2026, 2, 15)),
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 12, 1),
      );
      expect(dates, [DateTime(2026, 1, 1), DateTime(2026, 2, 1)]);
    });

    test('una regla inactiva no genera nada', () {
      final dates = occurrencesOf(
        _rule(nextDate: DateTime(2026, 1, 1), active: false),
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 6, 1),
      );
      expect(dates, isEmpty);
    });

    test('semanal con intervalo', () {
      final dates = occurrencesOf(
        _rule(
            nextDate: DateTime(2026, 1, 1),
            freq: RecurringFrequency.weekly,
            interval: 2),
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 31),
      );
      expect(dates, [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 15),
        DateTime(2026, 1, 29),
      ]);
    });
  });

  group('upcomingTimeline', () {
    test('mezcla y ordena por fecha, con el signo correcto', () {
      final rules = [
        _rule(nextDate: DateTime(2026, 1, 20), amountCents: 500),
        _rule(
            nextDate: DateTime(2026, 1, 5),
            type: TransactionType.income,
            amountCents: 2000),
      ];
      final tl = upcomingTimeline(rules,
          from: DateTime(2026, 1, 1), to: DateTime(2026, 1, 31));
      expect(tl.map((o) => o.date), [
        DateTime(2026, 1, 5),
        DateTime(2026, 1, 20),
      ]);
      expect(tl.first.signedCents, 2000); // ingreso
      expect(tl.last.signedCents, -500); // gasto
    });
  });
}
