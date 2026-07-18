/// Lógica pura de "cuándo toca la próxima copia": serie de ocurrencias a partir
/// de un ancla fija. Separada del orquestador para poder testearla sin Isar, sin
/// red y sin plugins (mismo patrón que `sync_reminder_planner.dart` y
/// `notification_planner.dart`).
library;

import '../../data/models/enums.dart';

/// Días que tiene [month] (1-12) en [year]. El día 0 del mes siguiente es el
/// último del actual, y `DateTime` ya cuenta los bisiestos.
int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Suma [months] meses recortando el día al último del mes destino
/// (31 ene + 1 mes = 28 feb; 29 feb en bisiesto). Conserva la hora.
DateTime addMonthsClamped(DateTime d, int months) {
  final total = d.year * 12 + (d.month - 1) + months;
  final year = (total / 12).floor();
  final month = total - year * 12 + 1;
  final maxDay = daysInMonth(year, month);
  return DateTime(
    year,
    month,
    d.day <= maxDay ? d.day : maxDay,
    d.hour,
    d.minute,
  );
}

/// Ocurrencia número [n] (0 = el propio [anchor]) de la serie que arranca en
/// [anchor] con la cadencia [freq] × [every].
///
/// Todas las ocurrencias se calculan **desde el ancla**, nunca encadenando desde
/// la anterior: encadenar haría que el recorte de fin de mes se realimentara
/// (31 ene → 28 feb → 28 mar → 28 abr…) y el día se adelantaría para siempre.
/// Anclado, la serie es 31 ene → 28 feb → 31 mar → 30 abr, sin deriva.
///
/// Los saltos de días usan el desbordamiento de `DateTime(y, m, d + k)` en vez
/// de `add(Duration(days: k))`: así la hora de pared se mantiene estable al
/// cruzar un cambio de horario de verano (`Duration` suma horas absolutas y
/// desplazaría una copia de las 03:00 a las 02:00 o las 04:00).
DateTime occurrenceAt({
  required DateTime anchor,
  required BackupFrequency freq,
  required int every,
  required int n,
}) {
  final step = every < 1 ? 1 : every;
  switch (freq) {
    case BackupFrequency.daily:
      return DateTime(
        anchor.year,
        anchor.month,
        anchor.day + n * step,
        anchor.hour,
        anchor.minute,
      );
    case BackupFrequency.weekly:
      return DateTime(
        anchor.year,
        anchor.month,
        anchor.day + n * step * 7,
        anchor.hour,
        anchor.minute,
      );
    case BackupFrequency.monthly:
      return addMonthsClamped(anchor, n * step);
  }
}

/// Primera ocurrencia **estrictamente posterior** a [after].
///
/// Estima el número de pasos por división entera y ajusta con dos bucles
/// acotados: la estimación puede fallar por uno (recortes de fin de mes,
/// cambios de horario), nunca por más.
DateTime nextOccurrenceAfter({
  required DateTime anchor,
  required BackupFrequency freq,
  required int every,
  required DateTime after,
}) {
  final step = every < 1 ? 1 : every;
  DateTime at(int n) =>
      occurrenceAt(anchor: anchor, freq: freq, every: step, n: n);

  var n = _estimateSteps(anchor, freq, step, after);
  if (n < 0) n = 0;

  // Guardas: la estimación deja `n` a un paso o dos del sitio. Un bucle sin
  // límite aquí sería un cuelgue silencioso si algún día se cuela un `freq`
  // nuevo mal estimado.
  var guard = 0;
  while (!at(n).isAfter(after) && guard++ < 8) {
    n++;
  }
  guard = 0;
  while (n > 0 && at(n - 1).isAfter(after) && guard++ < 8) {
    n--;
  }
  return at(n);
}

int _estimateSteps(
  DateTime anchor,
  BackupFrequency freq,
  int step,
  DateTime after,
) {
  switch (freq) {
    case BackupFrequency.daily:
      return after.difference(anchor).inDays ~/ step;
    case BackupFrequency.weekly:
      return after.difference(anchor).inDays ~/ (7 * step);
    case BackupFrequency.monthly:
      final months =
          (after.year - anchor.year) * 12 + (after.month - anchor.month);
      return months ~/ step;
  }
}

/// ¿Toca ya una copia?
///
/// Sin [lastRun] devuelve `true`: la primera copia se hace nada más activar la
/// feature, para que un error de configuración salte en el momento en vez de
/// dentro de un mes, cuando ya nadie lo relaciona.
bool isBackupDue({
  required DateTime anchor,
  required BackupFrequency freq,
  required int every,
  DateTime? lastRun,
  required DateTime now,
}) {
  if (lastRun == null) return true;
  final next = nextOccurrenceAfter(
    anchor: anchor,
    freq: freq,
    every: every,
    after: lastRun,
  );
  return !next.isAfter(now);
}

/// Reancla la serie a una hora nueva conservando el día. Se usa al cambiar la
/// hora preferida en Ajustes: mover la hora no debe cambiar en qué días cae.
DateTime reanchor(DateTime anchor, int hour, int minute) =>
    DateTime(anchor.year, anchor.month, anchor.day, hour, minute);

/// Etiqueta legible de una cadencia. Traduce las combinaciones con nombre
/// propio; el resto cae en "Cada N …".
String frequencyLabel(BackupFrequency freq, int every) {
  final n = every < 1 ? 1 : every;
  switch (freq) {
    case BackupFrequency.daily:
      return n == 1 ? 'Diaria' : 'Cada $n días';
    case BackupFrequency.weekly:
      if (n == 1) return 'Semanal';
      if (n == 2) return 'Cada 2 semanas';
      return 'Cada $n semanas';
    case BackupFrequency.monthly:
      switch (n) {
        case 1:
          return 'Mensual';
        case 3:
          return 'Trimestral';
        case 6:
          return 'Semestral';
        case 12:
          return 'Anual';
        default:
          return 'Cada $n meses';
      }
  }
}

/// Opciones con nombre propio que ofrece la UI. "Personalizada" no está aquí:
/// es la ausencia de preset (ver [presetFor]).
const kBackupPresets = <({BackupFrequency freq, int every})>[
  (freq: BackupFrequency.daily, every: 1),
  (freq: BackupFrequency.weekly, every: 1),
  (freq: BackupFrequency.monthly, every: 1),
  (freq: BackupFrequency.monthly, every: 3),
  (freq: BackupFrequency.monthly, every: 6),
  (freq: BackupFrequency.monthly, every: 12),
];

/// Índice del preset que casa con [freq] × [every], o `null` si es una cadencia
/// personalizada.
int? presetFor(BackupFrequency freq, int every) {
  final n = every < 1 ? 1 : every;
  for (var i = 0; i < kBackupPresets.length; i++) {
    if (kBackupPresets[i].freq == freq && kBackupPresets[i].every == n) return i;
  }
  return null;
}
