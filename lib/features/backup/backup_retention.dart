/// Lógica pura de nombrado y rotación de copias: cómo se llama una copia, cuáles
/// son nuestras y cuáles sobran. Sin red ni Isar, para poder testear la parte
/// que borra ficheros sin arriesgar ninguno.
library;

import '../../data/models/enums.dart';
import 'cloud_backup_provider.dart';

const _prefix = 'finanzas_backup_';
const _suffix = '.json';

/// Nombre de una copia hecha en [now].
///
/// El timestamp va en **UTC** (sufijo `Z`) a propósito: así el orden
/// lexicográfico de los nombres coincide *siempre* con el orden cronológico. Con
/// hora local, un cambio de horario de verano —o cruzar de zona al viajar— crea
/// nombres que ordenan al revés que los hechos, y la rotación acabaría borrando
/// la copia equivocada sin que salte nada.
String backupFilename(DateTime now) {
  final stamp =
      now.toUtc().toIso8601String().split('.').first.replaceAll(':', '-');
  return '$_prefix${stamp}Z$_suffix';
}

/// ¿Es [name] una copia creada por esta app?
///
/// La rotación **solo** toca lo que casa aquí: la carpeta de Nextcloud puede
/// estar compartida o tener otras cosas dentro, y borrar ficheros ajenos sería
/// imperdonable.
bool isBackupFilename(String name) =>
    name.startsWith(_prefix) && name.endsWith(_suffix);

/// Copias que sobran para dejar solo las [keepLast] más recientes.
///
/// Ordena por nombre (que es el timestamp UTC, ver [backupFilename]) en vez de
/// por `modifiedAt`: la fecha del servidor puede ir desincronizada, el nombre lo
/// puso quien hizo la copia. Ignora los ficheros que no sean nuestros.
/// [keepLast] <= 0 significa "conservarlas todas" y no borra nada.
List<BackupEntry> entriesToDelete(List<BackupEntry> entries, int keepLast) {
  if (keepLast <= 0) return const [];
  final ours = entries.where((e) => isBackupFilename(e.name)).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  if (ours.length <= keepLast) return const [];
  return ours.sublist(0, ours.length - keepLast);
}

/// Cuánto historial cubre de verdad la retención configurada.
///
/// No es un adorno de la UI: "conservar 10 copias" con frecuencia diaria son
/// **10 días** de historial. Si borras algo por error y lo notas tres semanas
/// después, la copia buena ya no existe. La pantalla de ajustes lo dice con
/// todas las letras para que la cifra no se lea como "10 copias = mucho".
Duration retentionHorizon(BackupFrequency freq, int every, int keepLast) {
  final n = every < 1 ? 1 : every;
  final k = keepLast < 1 ? 1 : keepLast;
  switch (freq) {
    case BackupFrequency.daily:
      return Duration(days: n * k);
    case BackupFrequency.weekly:
      return Duration(days: 7 * n * k);
    case BackupFrequency.monthly:
      // 30 días por mes: es una estimación para enseñar ("≈ 3 meses"), no una
      // fecha con la que se decida nada.
      return Duration(days: 30 * n * k);
  }
}

/// [retentionHorizon] en texto ("≈ 3 meses de historial").
String retentionHorizonLabel(BackupFrequency freq, int every, int keepLast) {
  final days = retentionHorizon(freq, every, keepLast).inDays;
  if (days < 14) return '≈ $days ${days == 1 ? 'día' : 'días'} de historial';
  if (days < 60) {
    final weeks = (days / 7).round();
    return '≈ $weeks ${weeks == 1 ? 'semana' : 'semanas'} de historial';
  }
  if (days < 730) {
    final months = (days / 30).round();
    return '≈ $months ${months == 1 ? 'mes' : 'meses'} de historial';
  }
  final years = (days / 365).round();
  return '≈ $years ${years == 1 ? 'año' : 'años'} de historial';
}
