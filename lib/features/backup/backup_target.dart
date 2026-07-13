/// Destino de una copia de seguridad: recibe el contenido ya serializado y lo
/// guarda/sube donde corresponda. Cada destino (archivo local, Nextcloud,
/// Google Drive) implementa esta interfaz para que el planificador
/// (`backup_scheduler_service.dart`) sea agnóstico del sitio de destino.
abstract class BackupTarget {
  /// Guarda/sube [bytes] con el nombre [filename]. **Lanza** si falla (el
  /// servicio lo captura, lo registra y avisa).
  Future<void> upload(String filename, List<int> bytes);

  /// Nombre legible del destino (para el registro y la UI de Ajustes).
  String get label;
}
