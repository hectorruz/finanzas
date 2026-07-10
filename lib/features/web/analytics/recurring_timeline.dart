import '../../../data/models/enums.dart';
import '../web_models.dart';

/// Una ocurrencia futura de una regla recurrente (para el timeline).
class RecurringOccurrence {
  const RecurringOccurrence(this.rule, this.date);
  final RecurringDto rule;
  final DateTime date;

  /// Efecto sobre el balance total (ingreso +, gasto -).
  int get signedCents =>
      rule.type == TransactionType.income ? rule.amountCents : -rule.amountCents;
}

DateTime _addMonths(DateTime d, int months) {
  final total = d.month - 1 + months;
  final year = d.year + (total ~/ 12);
  final month = (total % 12) + 1;
  final day = d.day;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day > lastDay ? lastDay : day);
}

DateTime _advance(DateTime d, RecurringFrequency freq, int interval) {
  final step = interval < 1 ? 1 : interval;
  switch (freq) {
    case RecurringFrequency.daily:
      return d.add(Duration(days: step));
    case RecurringFrequency.weekly:
      return d.add(Duration(days: 7 * step));
    case RecurringFrequency.monthly:
      return _addMonths(d, step);
    case RecurringFrequency.yearly:
      return _addMonths(d, 12 * step);
  }
}

/// Ocurrencias de una regla activa dentro de `[from, to]`, respetando su
/// `endDate`. Empieza en `nextDate` y avanza por frecuencia×intervalo. Acota el
/// número de iteraciones por seguridad.
List<DateTime> occurrencesOf(
  RecurringDto rule, {
  required DateTime from,
  required DateTime to,
}) {
  if (!rule.active) return const [];
  final out = <DateTime>[];
  var d = rule.nextDate;
  var guard = 0;
  while (!d.isAfter(to) && guard++ < 1000) {
    final beyondEnd = rule.endDate != null && d.isAfter(rule.endDate!);
    if (beyondEnd) break;
    if (!d.isBefore(from)) out.add(d);
    d = _advance(d, rule.frequency, rule.interval);
  }
  return out;
}

/// Todas las ocurrencias de todas las reglas en `[from, to]`, ordenadas por
/// fecha (timeline unificada de próximos cargos/ingresos).
List<RecurringOccurrence> upcomingTimeline(
  List<RecurringDto> rules, {
  required DateTime from,
  required DateTime to,
}) {
  final out = <RecurringOccurrence>[];
  for (final rule in rules) {
    for (final date in occurrencesOf(rule, from: from, to: to)) {
      out.add(RecurringOccurrence(rule, date));
    }
  }
  out.sort((a, b) => a.date.compareTo(b.date));
  return out;
}
