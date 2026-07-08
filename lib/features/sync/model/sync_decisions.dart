import 'entity_change.dart';

/// Qué versión gana en un conflicto, decidido por la persona en la revisión.
enum ConflictChoice {
  /// Se queda la versión del admin (el vinculado revierte la suya).
  keepLocal,

  /// Se queda la versión del vinculado (el admin la adopta).
  keepRemote,

  /// El admin compuso una tercera versión editada (ver
  /// [SyncDecisions.editedResolutions]).
  edited,
}

/// Decisiones del admin sobre un [SyncPlan] tras la revisión.
///
/// Por defecto todo lo no conflictivo (nuevos + actualizaciones limpias) se
/// aprueba; [deniedUuids] son las excepciones denegadas. Cada conflicto necesita
/// una elección en [conflictChoices]; si falta, se asume [ConflictChoice.keepLocal]
/// (no se aplica nada del vinculado: la opción más conservadora).
class SyncDecisions {
  SyncDecisions({
    Set<String>? deniedUuids,
    Map<String, ConflictChoice>? conflictChoices,
    Map<String, EntityChange>? editedResolutions,
  })  : deniedUuids = deniedUuids ?? <String>{},
        conflictChoices = conflictChoices ?? <String, ConflictChoice>{},
        editedResolutions = editedResolutions ?? <String, EntityChange>{};

  /// Uuids de additions/cleanUpdates que el admin denegó (no se aplican).
  final Set<String> deniedUuids;

  /// Elección por uuid de conflicto.
  final Map<String, ConflictChoice> conflictChoices;

  /// Versión compuesta por el admin cuando [ConflictChoice.edited].
  final Map<String, EntityChange> editedResolutions;

  ConflictChoice choiceFor(String uuid) =>
      conflictChoices[uuid] ?? ConflictChoice.keepLocal;
}
