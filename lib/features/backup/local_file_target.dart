import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'backup_target.dart';

/// Guarda las copias en un directorio dentro del almacenamiento de la app
/// (`.../backups/`) y rota, conservando como mucho [keepLast] ficheros (borra
/// los más antiguos). Para llevarse una copia fuera del dispositivo se sigue
/// usando "Exportar datos" (compartir), esto es la copia local persistente.
class LocalFileBackupTarget implements BackupTarget {
  LocalFileBackupTarget({this.keepLast = 10});

  final int keepLast;

  @override
  String get label => 'Archivo local';

  @override
  Future<void> upload(String filename, List<int> bytes) async {
    final dir = await backupsDir();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    await _rotate(dir);
  }

  /// Directorio de copias, creado si no existe.
  static Future<Directory> backupsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/backups');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Copias existentes, de la más reciente a la más antigua (para la UI). El
  /// nombre lleva la fecha ISO, que ordena igual cronológica que
  /// lexicográficamente.
  static Future<List<File>> listBackups() async {
    final dir = await backupsDir();
    final files = (await dir.list().toList())
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<void> _rotate(Directory dir) async {
    if (keepLast <= 0) return;
    final files = (await dir.list().toList())
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path)); // más antiguas primero
    final excess = files.length - keepLast;
    for (var i = 0; i < excess; i++) {
      try {
        await files[i].delete();
      } catch (_) {
        // Best-effort: si no se puede borrar una antigua, no rompemos la copia.
      }
    }
  }
}
