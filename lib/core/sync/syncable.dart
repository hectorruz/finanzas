/// Interfaz común de las entidades sincronizables entre dispositivos.
///
/// Toda colección de dominio que participa en la sincronización LAN
/// admin/vinculado expone tres campos de metadatos, además de su `Id` local:
///
/// - [uuid]: clave lógica **estable entre dispositivos** (los `Id` autoincrement
///   de Isar chocan al fusionar, el uuid no). Se genera una sola vez, en la
///   creación, y nunca cambia.
/// - [updatedAt]: marca de última modificación. Sirve para **detectar** qué ha
///   cambiado desde el último watermark; nunca para decidir automáticamente un
///   ganador en un conflicto (eso lo resuelve una persona en la pantalla de
///   revisión).
/// - [deletedAt]: *tombstone*. `null` = registro vivo; con valor = borrado
///   lógico. Sin esto, lo borrado en un móvil "resucitaría" al sincronizar.
///
/// Los campos se declaran **concretos en cada `@collection`** (Isar necesita
/// verlos en la clase, no valen campos heredados de un mixin); esta interfaz
/// solo aporta el tipo común para [stampForSave]/[stampForDelete].
abstract class Syncable {
  String get uuid;
  set uuid(String value);

  DateTime get updatedAt;
  set updatedAt(DateTime value);

  DateTime? get deletedAt;
  set deletedAt(DateTime? value);
}
