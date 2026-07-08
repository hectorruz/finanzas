import 'package:isar_community/isar.dart';

import '../../core/sync/syncable.dart';
import 'enums.dart';

part 'recurring_rule.g.dart';

/// Plantilla de movimiento recurrente (suscripciones, sueldos, etc.).
///
/// Un servicio "materializa" las ocurrencias pendientes generando
/// [TransactionModel] reales hasta la fecha actual cada vez que se abre la app.
@Collection(accessor: 'recurringRules')
class RecurringRule implements Syncable {
  Id id = Isar.autoIncrement;

  /// Metadatos de sincronización (ver [Syncable]).
  @override
  @Index()
  String uuid = '';
  @override
  DateTime updatedAt = DateTime.fromMillisecondsSinceEpoch(0);
  @override
  DateTime? deletedAt;

  late String name;

  @Enumerated(EnumType.name)
  TransactionType type = TransactionType.expense;

  int amountCents = 0;

  String concept = '';

  @Enumerated(EnumType.name)
  RecurringFrequency frequency = RecurringFrequency.monthly;

  /// Cada cuántas unidades de [frequency] se repite (p. ej. cada 2 meses).
  int interval = 1;

  /// Próxima fecha en la que debe generarse una ocurrencia.
  DateTime nextDate = DateTime.now();

  /// Fecha de fin opcional; si es null, no caduca.
  DateTime? endDate;

  bool active = true;

  int accountId = 0;
  int? categoryId;

  RecurringRule();

  /// Calcula la siguiente fecha a partir de [from] según frecuencia e intervalo.
  DateTime advance(DateTime from) {
    switch (frequency) {
      case RecurringFrequency.daily:
        return from.add(Duration(days: interval));
      case RecurringFrequency.weekly:
        return from.add(Duration(days: 7 * interval));
      case RecurringFrequency.monthly:
        return DateTime(from.year, from.month + interval, from.day);
      case RecurringFrequency.yearly:
        return DateTime(from.year + interval, from.month, from.day);
    }
  }
}
