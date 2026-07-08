import '../../../data/models/enums.dart';

/// Colecciones que participan en la sincronización, en **orden de dependencia**
/// (las referenciadas van antes que quienes las referencian). El aplicador usa
/// este orden para resolver claves foráneas sin referencias colgantes.
enum SyncCollection {
  account,
  category,
  recurringRule,
  receipt,
  transaction,
  goal;
}

/// Cambio de una entidad tal y como viaja entre dispositivos.
///
/// Es una foto **estable entre dispositivos**: la identidad es el [uuid] y las
/// claves foráneas viajan como uuids dentro de [data] (nunca como ids locales
/// autoincrement, que difieren de un móvil a otro). Los tombstones viajan con
/// [deletedAt] != null; el borrado es un cambio más, no un DELETE.
class EntityChange {
  EntityChange({
    required this.collection,
    required this.uuid,
    required this.updatedAt,
    required this.deletedAt,
    required this.data,
  });

  final SyncCollection collection;
  final String uuid;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// Campos de dominio; las FKs son `*Uuid` (o null). No incluye id local ni los
  /// metadatos (uuid/updatedAt/deletedAt), que van en los campos de arriba.
  final Map<String, dynamic> data;

  bool get isDeleted => deletedAt != null;

  Map<String, dynamic> toJson() => {
        'collection': collection.name,
        'uuid': uuid,
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'data': data,
      };

  static EntityChange fromJson(Map<String, dynamic> m) => EntityChange(
        collection: enumByName(
            SyncCollection.values, m['collection'] as String?,
            SyncCollection.transaction),
        uuid: m['uuid'] as String,
        updatedAt: DateTime.parse(m['updatedAt'] as String),
        deletedAt: m['deletedAt'] == null
            ? null
            : DateTime.parse(m['deletedAt'] as String),
        data: (m['data'] as Map).cast<String, dynamic>(),
      );

  EntityChange copyWith({Map<String, dynamic>? data, DateTime? updatedAt}) =>
      EntityChange(
        collection: collection,
        uuid: uuid,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt,
        data: data ?? this.data,
      );
}
