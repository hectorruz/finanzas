/// Lógica pura de la programación de copias de seguridad: si toca una copia
/// ahora y cuándo caería la próxima. Separada de WorkManager/plugins para
/// poder testearla sin plataforma (mismo patrón que `sync_reminder_planner.dart`
/// y `notification_planner.dart`).
library;

import '../../data/models/enums.dart';

/// Intervalo mínimo entre copias para cada frecuencia. El mensual se aproxima a
/// 30 días: encaja con la filosofía inexacta/best-effort de la app (los avisos y
/// las recurrentes tampoco son exactos al día del mes).
Duration backupInterval(BackupFrequency freq) => switch (freq) {
      BackupFrequency.daily => const Duration(days: 1),
      BackupFrequency.weekly => const Duration(days: 7),
      BackupFrequency.monthly => const Duration(days: 30),
    };

/// ¿Toca hacer una copia ahora? `true` si nunca se hizo ninguna, o si desde la
/// última ([lastRun]) ha pasado al menos el intervalo de la [freq].
bool isBackupDue({
  required BackupFrequency freq,
  DateTime? lastRun,
  required DateTime now,
}) {
  if (lastRun == null) return true;
  return !now.isBefore(lastRun.add(backupInterval(freq)));
}

/// Próxima fecha/hora (estrictamente futura respecto a [now]) en que debería
/// correr la copia: la hora preferida [hour]:[minute] del día en que vence el
/// intervalo desde la última copia (o de hoy si nunca se hizo). Solo se usa para
/// mostrar/planificar un aviso; el disparo real lo decide [isBackupDue].
DateTime nextBackupTime({
  required BackupFrequency freq,
  required int hour,
  int minute = 0,
  DateTime? lastRun,
  required DateTime now,
}) {
  final base = lastRun == null ? now : lastRun.add(backupInterval(freq));
  var candidate = DateTime(base.year, base.month, base.day, hour, minute);
  while (!candidate.isAfter(now)) {
    candidate = candidate.add(const Duration(days: 1));
  }
  return candidate;
}
