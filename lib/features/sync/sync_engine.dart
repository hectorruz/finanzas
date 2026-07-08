import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../../core/db/isar_provider.dart';
import '../../data/models/account.dart';
import '../../data/models/category.dart';
import '../../data/models/goal.dart';
import '../../data/models/receipt.dart';
import '../../data/models/recurring_rule.dart';
import '../../data/models/sync_peer.dart';
import '../../data/models/transaction.dart';
import 'model/entity_change.dart';
import 'model/sync_decisions.dart';
import 'model/sync_plan.dart';
import 'sync_codec.dart';

/// Resultado de una fusión en el lado admin: el estado **autoritativo** a
/// devolver al vinculado (para que reconcilie y quede idéntico) y el nuevo
/// watermark acordado.
class SyncMergeResult {
  SyncMergeResult({required this.authoritative, required this.newWatermark});

  /// Versión definitiva (post-fusión) de cada uuid que cambió en cualquiera de
  /// los dos lados desde el watermark. El vinculado hace upsert de todo esto.
  final List<EntityChange> authoritative;
  final DateTime newWatermark;
}

/// Motor de sincronización sobre Isar. No sabe de red: produce/consume listas de
/// [EntityChange], de modo que el transporte (LAN, fase 3) es intercambiable y
/// la lógica de fusión es testeable con dos instancias de Isar en memoria.
class SyncEngine {
  SyncEngine(this._isar, [this._codec = const SyncCodec()]);
  final Isar _isar;
  final SyncCodec _codec;

  // --- Changelog (cambios propios desde el watermark, para enviar) ---

  /// Todos los registros (incluidos tombstones) con `updatedAt` posterior a
  /// [since], codificados con las FKs como uuids.
  Future<List<EntityChange>> buildChangelog(DateTime since) async {
    final uuidOf = _uuidOfFrom(await _buildIdToUuid());
    final out = <EntityChange>[];

    for (final a
        in await _isar.accounts.filter().updatedAtGreaterThan(since).findAll()) {
      out.add(_codec.encodeAccount(a, uuidOf));
    }
    for (final c in await _isar.categories
        .filter()
        .updatedAtGreaterThan(since)
        .findAll()) {
      out.add(_codec.encodeCategory(c, uuidOf));
    }
    for (final r in await _isar.recurringRules
        .filter()
        .updatedAtGreaterThan(since)
        .findAll()) {
      out.add(_codec.encodeRecurring(r, uuidOf));
    }
    for (final r
        in await _isar.receipts.filter().updatedAtGreaterThan(since).findAll()) {
      out.add(_codec.encodeReceipt(r, uuidOf));
    }
    for (final t in await _isar.transactions
        .filter()
        .updatedAtGreaterThan(since)
        .findAll()) {
      out.add(_codec.encodeTransaction(t, uuidOf));
    }
    for (final g
        in await _isar.goals.filter().updatedAtGreaterThan(since).findAll()) {
      out.add(_codec.encodeGoal(g, uuidOf));
    }
    return out;
  }

  // --- Clasificación (admin: cambios entrantes vs estado propio) ---

  Future<SyncPlan> classifyIncoming(
    List<EntityChange> incoming,
    DateTime watermark,
  ) async {
    final uuidOf = _uuidOfFrom(await _buildIdToUuid());
    final localByUuid = <String, EntityChange>{};
    for (final change in incoming) {
      final local = await _encodeLocalByUuid(change.collection, change.uuid, uuidOf);
      if (local != null) localByUuid[change.uuid] = local;
    }
    return classifyChanges(
      incoming: incoming,
      localByUuid: localByUuid,
      watermark: watermark,
    );
  }

  // --- Fusión (admin) y reconciliación (vinculado) ---

  /// Aplica las decisiones del admin de forma **atómica** y devuelve el estado
  /// autoritativo para el vinculado. El watermark del par solo avanza aquí,
  /// dentro de la misma transacción que la fusión: si algo falla, ni se aplica a
  /// medias ni se mueve el watermark.
  Future<SyncMergeResult> mergeAsAdmin({
    required List<EntityChange> incoming,
    required List<EntityChange> ownChangelog,
    required SyncPlan plan,
    required SyncDecisions decisions,
    required DateTime newWatermark,
    int? peerId,
  }) async {
    final approved = _resolveApproved(plan, decisions, newWatermark);

    await _isar.writeTxn(() async {
      await _applyApprovedInTxn(approved);
      if (peerId != null) await _setWatermarkInTxn(peerId, newWatermark);
    });

    // Estado definitivo para el vinculado: la versión post-fusión de todo lo que
    // cambió en cualquiera de los dos lados (unión de uuids). Así el vinculado
    // adopta lo aprobado y revierte lo denegado quedando idéntico.
    final union = <SyncCollection, Set<String>>{};
    for (final c in [...incoming, ...ownChangelog]) {
      (union[c.collection] ??= <String>{}).add(c.uuid);
    }
    final uuidOf = _uuidOfFrom(await _buildIdToUuid());
    final authoritative = <EntityChange>[];
    for (final entry in union.entries) {
      for (final uuid in entry.value) {
        final current = await _encodeLocalByUuid(entry.key, uuid, uuidOf);
        if (current != null) authoritative.add(current);
      }
    }

    return SyncMergeResult(
        authoritative: authoritative, newWatermark: newWatermark);
  }

  /// Lado vinculado: adopta el estado autoritativo del admin (idéntico) y avanza
  /// el watermark, todo atómico.
  Future<void> reconcileAsLinked(
    List<EntityChange> authoritative, {
    required DateTime newWatermark,
    int? peerId,
  }) async {
    await _isar.writeTxn(() async {
      await _applyApprovedInTxn(authoritative);
      if (peerId != null) await _setWatermarkInTxn(peerId, newWatermark);
    });
  }

  /// Traduce plan + decisiones a la lista de cambios a aplicar en la BD del
  /// admin. Una addition denegada se materializa como **tombstone** (no como
  /// "no hacer nada") para que el vinculado también la retire y ambas BD queden
  /// idénticas; nada se destruye en silencio.
  List<EntityChange> _resolveApproved(
    SyncPlan plan,
    SyncDecisions decisions,
    DateTime now,
  ) {
    final approved = <EntityChange>[];

    for (final c in plan.additions) {
      if (decisions.deniedUuids.contains(c.uuid)) {
        approved.add(_asTombstone(c, now));
      } else {
        approved.add(c);
      }
    }

    for (final c in plan.cleanUpdates) {
      if (!decisions.deniedUuids.contains(c.uuid)) approved.add(c);
      // Denegada: el admin conserva su versión (no se aplica nada).
    }

    for (final conflict in plan.conflicts) {
      switch (decisions.choiceFor(conflict.uuid)) {
        case ConflictChoice.keepRemote:
          approved.add(conflict.remote);
        case ConflictChoice.edited:
          final edited = decisions.editedResolutions[conflict.uuid];
          if (edited != null) approved.add(edited);
        case ConflictChoice.keepLocal:
          break; // el admin mantiene su versión
      }
    }

    return approved;
  }

  EntityChange _asTombstone(EntityChange c, DateTime now) => EntityChange(
        collection: c.collection,
        uuid: c.uuid,
        updatedAt: now,
        deletedAt: now,
        data: c.data,
      );

  // --- Aplicación en dos fases (resuelve FKs con referencias hacia adelante) ---

  Future<void> _applyApprovedInTxn(List<EntityChange> approved) async {
    if (approved.isEmpty) return;

    // Mapa uuid->id de TODO lo local (incluye tombstones: una FK puede apuntar a
    // una fila borrada).
    final ids = await _buildUuidToId();
    int? idOf(SyncCollection col, String? uuid) =>
        uuid == null ? null : ids['${col.name}:$uuid'];

    final models = <String, Object>{};

    // Fase A: crear/cargar cada fila y ponerla para obtener id (las FKs hacia
    // filas aún no creadas quedan sin resolver de momento).
    final ordered = [...approved]
      ..sort((a, b) => a.collection.index.compareTo(b.collection.index));
    for (final c in ordered) {
      final key = '${c.collection.name}:${c.uuid}';
      final existingId = ids[key];
      final model = existingId != null
          ? await _loadById(c.collection, existingId)
          : _newModel(c.collection);
      _apply(model, c, idOf);
      ids[key] = await _put(c.collection, model);
      models[key] = model;
    }

    // Fase B: reaplicar con el mapa completo para fijar las FKs hacia adelante.
    for (final c in approved) {
      final key = '${c.collection.name}:${c.uuid}';
      final model = models[key]!;
      _apply(model, c, idOf);
      await _put(c.collection, model);
    }
  }

  // --- Watermark / peers ---

  Future<void> _setWatermarkInTxn(int peerId, DateTime watermark) async {
    final peer = await _isar.syncPeers.get(peerId);
    if (peer == null) return;
    peer
      ..watermark = watermark
      ..lastSyncAt = DateTime.now();
    await _isar.syncPeers.put(peer);
  }

  // --- Helpers de codificación / mapas ---

  /// key `'${collection}:$localId'` -> uuid, sobre todas las filas.
  Future<Map<String, String>> _buildIdToUuid() async {
    final m = <String, String>{};
    for (final a in await _isar.accounts.where().findAll()) {
      m['account:${a.id}'] = a.uuid;
    }
    for (final c in await _isar.categories.where().findAll()) {
      m['category:${c.id}'] = c.uuid;
    }
    for (final r in await _isar.recurringRules.where().findAll()) {
      m['recurringRule:${r.id}'] = r.uuid;
    }
    for (final r in await _isar.receipts.where().findAll()) {
      m['receipt:${r.id}'] = r.uuid;
    }
    for (final t in await _isar.transactions.where().findAll()) {
      m['transaction:${t.id}'] = t.uuid;
    }
    return m;
  }

  /// key `'${collection}:$uuid'` -> localId, sobre todas las filas.
  Future<Map<String, int>> _buildUuidToId() async {
    final m = <String, int>{};
    for (final a in await _isar.accounts.where().findAll()) {
      m['account:${a.uuid}'] = a.id;
    }
    for (final c in await _isar.categories.where().findAll()) {
      m['category:${c.uuid}'] = c.id;
    }
    for (final r in await _isar.recurringRules.where().findAll()) {
      m['recurringRule:${r.uuid}'] = r.id;
    }
    for (final r in await _isar.receipts.where().findAll()) {
      m['receipt:${r.uuid}'] = r.id;
    }
    for (final t in await _isar.transactions.where().findAll()) {
      m['transaction:${t.uuid}'] = t.id;
    }
    for (final g in await _isar.goals.where().findAll()) {
      m['goal:${g.uuid}'] = g.id;
    }
    return m;
  }

  UuidOf _uuidOfFrom(Map<String, String> m) =>
      (col, id) => id == null ? null : m['${col.name}:$id'];

  Future<EntityChange?> _encodeLocalByUuid(
      SyncCollection col, String uuid, UuidOf uuidOf) async {
    switch (col) {
      case SyncCollection.account:
        final a = await _isar.accounts.filter().uuidEqualTo(uuid).findFirst();
        return a == null ? null : _codec.encodeAccount(a, uuidOf);
      case SyncCollection.category:
        final c = await _isar.categories.filter().uuidEqualTo(uuid).findFirst();
        return c == null ? null : _codec.encodeCategory(c, uuidOf);
      case SyncCollection.recurringRule:
        final r =
            await _isar.recurringRules.filter().uuidEqualTo(uuid).findFirst();
        return r == null ? null : _codec.encodeRecurring(r, uuidOf);
      case SyncCollection.receipt:
        final r = await _isar.receipts.filter().uuidEqualTo(uuid).findFirst();
        return r == null ? null : _codec.encodeReceipt(r, uuidOf);
      case SyncCollection.transaction:
        final t = await _isar.transactions.filter().uuidEqualTo(uuid).findFirst();
        return t == null ? null : _codec.encodeTransaction(t, uuidOf);
      case SyncCollection.goal:
        final g = await _isar.goals.filter().uuidEqualTo(uuid).findFirst();
        return g == null ? null : _codec.encodeGoal(g, uuidOf);
    }
  }

  // --- Dispatch por colección (new / load / apply / put) ---

  Object _newModel(SyncCollection col) {
    switch (col) {
      case SyncCollection.account:
        return Account();
      case SyncCollection.category:
        return Category();
      case SyncCollection.recurringRule:
        return RecurringRule();
      case SyncCollection.receipt:
        return Receipt();
      case SyncCollection.transaction:
        return TransactionModel();
      case SyncCollection.goal:
        return Goal();
    }
  }

  Future<Object> _loadById(SyncCollection col, int id) async {
    switch (col) {
      case SyncCollection.account:
        return await _isar.accounts.get(id) ?? Account();
      case SyncCollection.category:
        return await _isar.categories.get(id) ?? Category();
      case SyncCollection.recurringRule:
        return await _isar.recurringRules.get(id) ?? RecurringRule();
      case SyncCollection.receipt:
        return await _isar.receipts.get(id) ?? Receipt();
      case SyncCollection.transaction:
        return await _isar.transactions.get(id) ?? TransactionModel();
      case SyncCollection.goal:
        return await _isar.goals.get(id) ?? Goal();
    }
  }

  void _apply(Object model, EntityChange c, IdOf idOf) {
    switch (c.collection) {
      case SyncCollection.account:
        _codec.applyAccount(model as Account, c, idOf);
      case SyncCollection.category:
        _codec.applyCategory(model as Category, c, idOf);
      case SyncCollection.recurringRule:
        _codec.applyRecurring(model as RecurringRule, c, idOf);
      case SyncCollection.receipt:
        _codec.applyReceipt(model as Receipt, c, idOf);
      case SyncCollection.transaction:
        _codec.applyTransaction(model as TransactionModel, c, idOf);
      case SyncCollection.goal:
        _codec.applyGoal(model as Goal, c, idOf);
    }
  }

  Future<int> _put(SyncCollection col, Object model) {
    switch (col) {
      case SyncCollection.account:
        return _isar.accounts.put(model as Account);
      case SyncCollection.category:
        return _isar.categories.put(model as Category);
      case SyncCollection.recurringRule:
        return _isar.recurringRules.put(model as RecurringRule);
      case SyncCollection.receipt:
        return _isar.receipts.put(model as Receipt);
      case SyncCollection.transaction:
        return _isar.transactions.put(model as TransactionModel);
      case SyncCollection.goal:
        return _isar.goals.put(model as Goal);
    }
  }
}

final syncEngineProvider = Provider<SyncEngine>(
  (ref) => SyncEngine(ref.watch(isarProvider)),
);
