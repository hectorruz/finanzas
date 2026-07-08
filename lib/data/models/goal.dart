import 'package:isar_community/isar.dart';

import '../../core/sync/syncable.dart';

part 'goal.g.dart';

/// Objetivo de ahorro configurable (módulo opcional del dashboard).
@Collection(accessor: 'goals')
class Goal implements Syncable {
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

  /// Cantidad objetivo en céntimos.
  int targetCents = 0;

  /// Cantidad acumulada en céntimos.
  int currentCents = 0;

  String iconName = 'flag';

  int colorValue = 0xFF4CAF50;

  DateTime? deadline;

  /// Aporte previsto cada mes, en céntimos (modo 'contribution').
  int monthlyContributionCents = 0;

  /// Modo de planificación: 'contribution' (aporto X/mes → tiempo) o
  /// 'deadline' (fijo fecha → aporte mensual necesario).
  String planMode = 'contribution';

  int sortOrder = 0;

  Goal();

  /// Progreso entre 0.0 y 1.0.
  @ignore
  double get progress {
    if (targetCents <= 0) return 0;
    return (currentCents / targetCents).clamp(0.0, 1.0);
  }

  /// Cantidad que aún falta para alcanzar el objetivo (en céntimos).
  @ignore
  int get remainingCents => (targetCents - currentCents).clamp(0, targetCents);

  /// Meses estimados para alcanzar el objetivo con el aporte mensual previsto
  /// (modo 'contribution'). `null` si no aplica o falta info.
  @ignore
  int? get monthsToTarget {
    if (planMode != 'contribution' || monthlyContributionCents <= 0) return null;
    if (remainingCents <= 0) return 0;
    return (remainingCents / monthlyContributionCents).ceil();
  }

  /// Fecha estimada de consecución (modo 'contribution').
  @ignore
  DateTime? get projectedDate {
    final months = monthsToTarget;
    if (months == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month + months, now.day);
  }

  /// Aporte mensual necesario para llegar a la fecha límite (modo 'deadline').
  /// `null` si no aplica o la fecha ya pasó.
  @ignore
  int? get requiredMonthlyCents {
    if (planMode != 'deadline' || deadline == null) return null;
    if (remainingCents <= 0) return 0;
    final now = DateTime.now();
    var months = (deadline!.year - now.year) * 12 + (deadline!.month - now.month);
    if (deadline!.day > now.day) months += 1; // mes en curso parcial
    if (months <= 0) return null;
    return (remainingCents / months).ceil();
  }
}
