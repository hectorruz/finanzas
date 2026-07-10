import 'package:isar_community/isar.dart';

import '../../core/planning/goal_planning.dart';
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

  // La matemática de planificación vive en `core/planning/goal_planning.dart`
  // (pura, sin Isar) para compartirla con el `GoalDto` de la webapp.

  /// Progreso entre 0.0 y 1.0.
  @ignore
  double get progress => goalProgress(currentCents, targetCents);

  /// Cantidad que aún falta para alcanzar el objetivo (en céntimos).
  @ignore
  int get remainingCents => goalRemainingCents(currentCents, targetCents);

  /// Meses estimados para alcanzar el objetivo con el aporte mensual previsto
  /// (modo 'contribution'). `null` si no aplica o falta info.
  @ignore
  int? get monthsToTarget => goalMonthsToTarget(
        planMode: planMode,
        monthlyContributionCents: monthlyContributionCents,
        remainingCents: remainingCents,
      );

  /// Fecha estimada de consecución (modo 'contribution').
  @ignore
  DateTime? get projectedDate => goalProjectedDate(
        planMode: planMode,
        monthlyContributionCents: monthlyContributionCents,
        remainingCents: remainingCents,
      );

  /// Aporte mensual necesario para llegar a la fecha límite (modo 'deadline').
  /// `null` si no aplica o la fecha ya pasó.
  @ignore
  int? get requiredMonthlyCents => goalRequiredMonthlyCents(
        planMode: planMode,
        deadline: deadline,
        remainingCents: remainingCents,
      );
}
