import 'package:uuid/uuid.dart';

import 'syncable.dart';

/// Generador de uuid v4 compartido (barato de reutilizar).
const Uuid _uuid = Uuid();

/// Sella una entidad [Syncable] justo **antes de guardarla**.
///
/// - Le asigna un [Syncable.uuid] la primera vez (si está vacío); en sucesivas
///   ediciones lo conserva, porque es la clave lógica estable de la fila.
/// - Actualiza [Syncable.updatedAt] al instante [now] (o `DateTime.now()`), para
///   que el sync pueda detectar el cambio.
/// - **No** toca [Syncable.deletedAt]: guardar no resucita ni borra.
///
/// Es la única fuente de verdad para el sellado; todos los repositorios la
/// llaman en su `save`/bulk antes del `put`.
void stampForSave(Syncable entity, {DateTime? now}) {
  if (entity.uuid.isEmpty) {
    entity.uuid = _uuid.v4();
  }
  entity.updatedAt = now ?? DateTime.now();
}

/// Sella una entidad [Syncable] como **borrada** (tombstone).
///
/// Fija [Syncable.deletedAt] y [Syncable.updatedAt] al mismo instante [now] (o
/// `DateTime.now()`), de modo que el borrado se propague como una modificación
/// más y nunca como un DELETE físico. Garantiza que la fila tenga uuid.
void stampForDelete(Syncable entity, {DateTime? now}) {
  final at = now ?? DateTime.now();
  if (entity.uuid.isEmpty) {
    entity.uuid = _uuid.v4();
  }
  entity.deletedAt = at;
  entity.updatedAt = at;
}
