/// Contrato común de los destinos de copias en la nube (Nextcloud, Google
/// Drive). Los proveedores solo hablan con su servicio: no saben de Isar, ni de
/// ajustes, ni de cuándo toca copiar ni de qué se conserva — eso vive en
/// `BackupSchedulerService` y en `backup_retention.dart`.
library;

/// Una copia ya existente en el destino remoto.
class BackupEntry {
  const BackupEntry({
    required this.id,
    required this.name,
    this.modifiedAt,
    this.sizeBytes,
  });

  /// Identificador con el que borrar o descargar: la ruta WebDAV en Nextcloud,
  /// el `fileId` en Drive.
  final String id;

  /// Nombre del fichero (`finanzas_backup_<ISO-UTC>.json`).
  final String name;

  final DateTime? modifiedAt;
  final int? sizeBytes;
}

/// Fallo al hablar con el destino. Su [message] se enseña tal cual al usuario,
/// así que va en español y sin jerga.
class CloudBackupException implements Exception {
  CloudBackupException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      statusCode == null ? message : '$message (HTTP $statusCode)';
}

/// Un sitio donde guardar copias.
///
/// Todos los métodos **lanzan** [CloudBackupException] si algo falla; ninguno
/// devuelve un valor "vacío" ante un error. Quien orquesta captura, registra el
/// motivo en los ajustes y avisa: un fallo que se degrada en silencio aquí
/// dejaría al usuario creyendo que tiene copias cuando no las tiene.
abstract class CloudBackupProvider {
  /// Nombre legible del destino, para los mensajes de estado ("Nextcloud").
  String get label;

  /// Sube [bytes] como [filename]. Sobrescribe si ya existe.
  Future<void> upload(String filename, List<int> bytes);

  /// Copias presentes en el destino. Puede incluir ficheros ajenos: filtrarlos
  /// es cosa de `isBackupFilename`.
  Future<List<BackupEntry>> list();

  Future<List<int>> download(BackupEntry entry);

  Future<void> delete(BackupEntry entry);

  /// Comprueba credenciales y carpeta sin llegar a subir una copia real.
  Future<void> testConnection();

  void close();
}
