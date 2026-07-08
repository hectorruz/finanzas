import '../../core/money/money.dart';
import '../../data/models/recurring_rule.dart';

/// Un aviso planificado para una regla recurrente. Es un dato puro (sin plugin)
/// para poder testear la lógica de fechas sin Android.
class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.when,
  });

  /// Id estable de la notificación (el id de la regla): reprogramar sustituye.
  final int id;
  final String title;
  final String body;
  final DateTime when;
}

/// Momento del aviso para la ocurrencia [occurrence] de [rule]: `notifyDaysBefore`
/// días antes, a la hora configurada (hora local).
DateTime computeNotifyTime(RecurringRule rule, DateTime occurrence) {
  final day = DateTime(occurrence.year, occurrence.month, occurrence.day)
      .subtract(Duration(days: rule.notifyDaysBefore));
  return DateTime(day.year, day.month, day.day, rule.notifyHour, rule.notifyMinute);
}

/// Planifica el próximo aviso de cada regla activa con notificación habilitada.
///
/// El aviso es **pasivo**: solo informa. El cargo se anota siempre
/// automáticamente (vía `materializeDue`), sin pedir confirmación. Por eso solo
/// se planifican avisos **futuros**: si la hora ya pasó, no hay nada que avisar
/// (la ocurrencia se materializa igualmente).
List<PlannedNotification> planNotifications(
  List<RecurringRule> rules, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final out = <PlannedNotification>[];

  for (final rule in rules) {
    if (!rule.active || !rule.notifyEnabled || rule.deletedAt != null) continue;

    // Busca la primera ocurrencia cuyo aviso aún es futuro (límite de seguridad).
    var occurrence = rule.nextDate;
    var guard = 0;
    DateTime? when;
    while (guard < 366) {
      if (rule.endDate != null && occurrence.isAfter(rule.endDate!)) break;
      final t = computeNotifyTime(rule, occurrence);
      if (t.isAfter(at)) {
        when = t;
        break;
      }
      occurrence = rule.advance(occurrence);
      guard++;
    }
    if (when == null) continue;

    out.add(PlannedNotification(
      id: rule.id,
      title: rule.name.isEmpty ? 'Cargo recurrente' : rule.name,
      body: _bodyFor(rule, occurrence),
      when: when,
    ));
  }

  out.sort((a, b) => a.when.compareTo(b.when));
  return out;
}

String _bodyFor(RecurringRule rule, DateTime occurrence) {
  final amount = Money(rule.amountCents).format();
  final concept = rule.concept.isEmpty ? rule.name : rule.concept;
  switch (rule.notifyDaysBefore) {
    case 0:
      return 'Hoy se anota "$concept" ($amount). Se registrará automáticamente.';
    case 1:
      return 'Mañana se anota "$concept" ($amount).';
    default:
      return 'En ${rule.notifyDaysBefore} días se anota "$concept" ($amount).';
  }
}
