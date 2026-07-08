import 'dart:convert';

import 'entity_change.dart';

/// Un conflicto: ambos dispositivos modificaron la misma entidad (por uuid)
/// desde el último watermark. Incluye el caso "uno la borró y el otro la editó"
/// (mira [local]/[remote] `isDeleted`). Lo resuelve una persona, nunca el reloj.
class SyncConflict {
  SyncConflict({required this.local, required this.remote});

  /// Versión del dispositivo que arbitra (admin).
  final EntityChange local;

  /// Versión del dispositivo vinculado.
  final EntityChange remote;

  String get uuid => remote.uuid;
  SyncCollection get collection => remote.collection;
}

/// Clasificación de los cambios entrantes contra el estado local del admin.
/// Los tres cubos son disjuntos y agotan los cambios que requieren atención.
class SyncPlan {
  SyncPlan({
    required this.additions,
    required this.cleanUpdates,
    required this.conflicts,
  });

  /// Uuids que el admin no tiene → candidatos a añadir.
  final List<EntityChange> additions;

  /// Uuids que existen y el admin **no** tocó desde el watermark → candidatos a
  /// aplicar sin conflicto.
  final List<EntityChange> cleanUpdates;

  /// Ambos los tocaron desde el watermark → requieren decisión humana.
  final List<SyncConflict> conflicts;

  bool get isEmpty =>
      additions.isEmpty && cleanUpdates.isEmpty && conflicts.isEmpty;

  int get total => additions.length + cleanUpdates.length + conflicts.length;
}

/// Clasifica cada [incoming] (cambios del vinculado desde el watermark) contra
/// [localByUuid] (estado actual del admin, indexado por uuid).
///
/// Regla: el timestamp solo **detecta** el cambio; el conflicto lo decide una
/// persona. Un cambio entrante es:
/// - **addition** si el admin no tiene ese uuid;
/// - **cleanUpdate** si existe y el admin no lo modificó desde el watermark;
/// - **conflict** si ambos lo modificaron desde el watermark.
///
/// Si ambas versiones son idénticas (mismo contenido y mismo estado de borrado)
/// se descarta: no hay nada que decidir ni aplicar.
SyncPlan classifyChanges({
  required List<EntityChange> incoming,
  required Map<String, EntityChange> localByUuid,
  required DateTime watermark,
}) {
  final additions = <EntityChange>[];
  final cleanUpdates = <EntityChange>[];
  final conflicts = <SyncConflict>[];

  for (final remote in incoming) {
    final local = localByUuid[remote.uuid];

    if (local == null) {
      additions.add(remote);
      continue;
    }

    if (_sameContent(local, remote)) {
      // Convergieron por su cuenta: nada que hacer.
      continue;
    }

    final adminTouched = local.updatedAt.isAfter(watermark);
    if (adminTouched) {
      conflicts.add(SyncConflict(local: local, remote: remote));
    } else {
      cleanUpdates.add(remote);
    }
  }

  return SyncPlan(
    additions: additions,
    cleanUpdates: cleanUpdates,
    conflicts: conflicts,
  );
}

/// Igualdad de contenido: mismo estado de borrado y mismos campos de dominio.
/// Ignora `updatedAt` a propósito (dos ediciones idénticas no son un conflicto).
bool _sameContent(EntityChange a, EntityChange b) {
  if ((a.deletedAt == null) != (b.deletedAt == null)) return false;
  return jsonEncode(a.data) == jsonEncode(b.data);
}
