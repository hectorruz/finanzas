import 'package:intl/intl.dart';

import '../money/money.dart';

/// Matemática **pura** de planificación de objetivos de ahorro, sin dependencias
/// de Isar. La comparten el modelo `Goal` (móvil) y el `GoalDto` de la webapp de
/// escritorio, para que la lógica viva en un único sitio.

/// Progreso entre 0.0 y 1.0.
double goalProgress(int currentCents, int targetCents) {
  if (targetCents <= 0) return 0;
  return (currentCents / targetCents).clamp(0.0, 1.0);
}

/// Cantidad que aún falta para alcanzar el objetivo (en céntimos, nunca negativa).
int goalRemainingCents(int currentCents, int targetCents) =>
    (targetCents - currentCents).clamp(0, targetCents);

/// Meses estimados para alcanzar el objetivo con el aporte mensual previsto
/// (modo 'contribution'). `null` si no aplica o falta info.
int? goalMonthsToTarget({
  required String planMode,
  required int monthlyContributionCents,
  required int remainingCents,
}) {
  if (planMode != 'contribution' || monthlyContributionCents <= 0) return null;
  if (remainingCents <= 0) return 0;
  return (remainingCents / monthlyContributionCents).ceil();
}

/// Fecha estimada de consecución (modo 'contribution').
DateTime? goalProjectedDate({
  required String planMode,
  required int monthlyContributionCents,
  required int remainingCents,
  DateTime? now,
}) {
  final months = goalMonthsToTarget(
    planMode: planMode,
    monthlyContributionCents: monthlyContributionCents,
    remainingCents: remainingCents,
  );
  if (months == null) return null;
  final n = now ?? DateTime.now();
  return DateTime(n.year, n.month + months, n.day);
}

/// Aporte mensual necesario para llegar a la fecha límite (modo 'deadline').
/// `null` si no aplica o la fecha ya pasó.
int? goalRequiredMonthlyCents({
  required String planMode,
  required DateTime? deadline,
  required int remainingCents,
  DateTime? now,
}) {
  if (planMode != 'deadline' || deadline == null) return null;
  if (remainingCents <= 0) return 0;
  final n = now ?? DateTime.now();
  var months = (deadline.year - n.year) * 12 + (deadline.month - n.month);
  if (deadline.day > n.day) months += 1; // mes en curso parcial
  if (months <= 0) return null;
  return (remainingCents / months).ceil();
}

/// Texto de planificación para mostrar bajo el progreso (lista, dashboard, web).
String? goalPlanLabelFor({
  required int currentCents,
  required int targetCents,
  required String planMode,
  required int monthlyContributionCents,
  DateTime? deadline,
  DateTime? now,
}) {
  final remaining = goalRemainingCents(currentCents, targetCents);
  if (remaining <= 0) return '¡Objetivo conseguido!';
  if (planMode == 'contribution') {
    final months = goalMonthsToTarget(
      planMode: planMode,
      monthlyContributionCents: monthlyContributionCents,
      remainingCents: remaining,
    );
    final date = goalProjectedDate(
      planMode: planMode,
      monthlyContributionCents: monthlyContributionCents,
      remainingCents: remaining,
      now: now,
    );
    if (months == null || date == null) return null;
    final when = DateFormat('MMM yyyy', 'es').format(date);
    return 'Lo alcanzas en ~$months ${months == 1 ? 'mes' : 'meses'} ($when)';
  } else {
    final monthly = goalRequiredMonthlyCents(
      planMode: planMode,
      deadline: deadline,
      remainingCents: remaining,
      now: now,
    );
    if (monthly == null) return null;
    return 'Necesitas ${Money(monthly).format()}/mes';
  }
}
