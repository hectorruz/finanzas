import 'package:finanzas/features/sync/sync_reminder_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mismo día de la semana, hora futura → hoy', () {
    final now = DateTime(2026, 7, 8, 10, 0); // miércoles
    final next = nextReminderOccurrence(
        weekday: DateTime.wednesday, hour: 20, minute: 0, now: now);
    expect(next, DateTime(2026, 7, 8, 20, 0));
  });

  test('mismo día de la semana, hora ya pasada → semana que viene', () {
    final now = DateTime(2026, 7, 8, 21, 0); // miércoles, ya pasó las 20:00
    final next = nextReminderOccurrence(
        weekday: DateTime.wednesday, hour: 20, minute: 0, now: now);
    expect(next, DateTime(2026, 7, 15, 20, 0));
  });

  test('otro día de la semana → la próxima vez que caiga', () {
    final now = DateTime(2026, 7, 8, 10, 0); // miércoles
    final next = nextReminderOccurrence(
        weekday: DateTime.friday, hour: 9, minute: 30, now: now);
    expect(next, DateTime(2026, 7, 10, 9, 30));
  });

  test('resolveReminderWeekdays: vacío → todos los días', () {
    expect(resolveReminderWeekdays(const []), allWeekdays);
  });

  test('resolveReminderWeekdays: configurado → tal cual', () {
    expect(resolveReminderWeekdays(const [1, 3, 5]), [1, 3, 5]);
  });
}
