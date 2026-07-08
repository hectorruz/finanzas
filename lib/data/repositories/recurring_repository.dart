import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../../core/db/isar_provider.dart';
import '../../core/sync/sync_stamp.dart';
import '../models/recurring_rule.dart';
import '../models/transaction.dart';

class RecurringRepository {
  RecurringRepository(this._isar);
  final Isar _isar;

  Stream<List<RecurringRule>> watchAll() {
    return _isar.recurringRules
        .filter()
        .deletedAtIsNull()
        .sortByNextDate()
        .watch(fireImmediately: true);
  }

  Future<int> save(RecurringRule rule) {
    stampForSave(rule);
    return _isar.writeTxn(() => _isar.recurringRules.put(rule));
  }

  /// Borrado lógico (tombstone) para que se propague en la sincronización.
  Future<void> delete(int id) {
    return _isar.writeTxn(() async {
      final rule = await _isar.recurringRules.get(id);
      if (rule == null) return;
      stampForDelete(rule);
      await _isar.recurringRules.put(rule);
    });
  }

  /// Genera los movimientos pendientes de todas las reglas activas hasta [now].
  ///
  /// Devuelve cuántos movimientos se crearon. Es idempotente: cada llamada solo
  /// genera las ocurrencias cuya `nextDate` ya ha pasado, avanzando la regla.
  Future<int> materializeDue([DateTime? now]) async {
    final today = now ?? DateTime.now();
    var created = 0;

    final rules = await _isar.recurringRules
        .filter()
        .deletedAtIsNull()
        .activeEqualTo(true)
        .findAll();

    await _isar.writeTxn(() async {
      for (final rule in rules) {
        var next = rule.nextDate;
        // Límite de seguridad para evitar bucles infinitos por datos erróneos.
        var guard = 0;
        while (!next.isAfter(today) && guard < 1000) {
          if (rule.endDate != null && next.isAfter(rule.endDate!)) break;

          final txn = TransactionModel()
            ..type = rule.type
            ..amountCents = rule.amountCents
            ..concept = rule.concept.isEmpty ? rule.name : rule.concept
            ..date = next
            ..accountId = rule.accountId
            ..categoryId = rule.categoryId
            ..recurringRuleId = rule.id;
          // Movimiento auto-creado: sellar como el resto para que entre en sync.
          stampForSave(txn, now: today);
          await _isar.transactions.put(txn);
          created++;

          next = rule.advance(next);
          guard++;
        }
        if (next != rule.nextDate) {
          rule.nextDate = next;
          stampForSave(rule, now: today);
          await _isar.recurringRules.put(rule);
        }
      }
    });

    return created;
  }
}

final recurringRepositoryProvider = Provider<RecurringRepository>(
  (ref) => RecurringRepository(ref.watch(isarProvider)),
);

final recurringRulesProvider = StreamProvider<List<RecurringRule>>(
  (ref) => ref.watch(recurringRepositoryProvider).watchAll(),
);
