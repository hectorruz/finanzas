/// Lógica pura del recordatorio de sincronización: cuándo debe sonar el
/// próximo aviso para un día de la semana y una hora dados. Separada del
/// plugin de notificaciones para poder testearla sin él (mismo patrón que
/// `notification_planner.dart` para las recurrentes).
library;

/// Próxima fecha/hora (estrictamente futura) en que cae [weekday]
/// (`DateTime.monday`..`DateTime.sunday`) a las [hour]:[minute], contando
/// desde [now].
DateTime nextReminderOccurrence({
  required int weekday,
  required int hour,
  required int minute,
  DateTime? now,
}) {
  final n = now ?? DateTime.now();
  var candidate = DateTime(n.year, n.month, n.day, hour, minute);
  while (candidate.weekday != weekday || !candidate.isAfter(n)) {
    candidate = candidate.add(const Duration(days: 1));
  }
  return candidate;
}

/// Días de la semana en que debe sonar el aviso (`DateTime.monday`..`sunday`).
/// Una lista vacía en los ajustes significa "todos los días".
const allWeekdays = [1, 2, 3, 4, 5, 6, 7];

List<int> resolveReminderWeekdays(List<int> configured) =>
    configured.isEmpty ? allWeekdays : configured;
