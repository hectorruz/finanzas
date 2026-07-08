import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../../core/db/isar_provider.dart';
import '../../core/sync/sync_stamp.dart';
import '../models/goal.dart';

class GoalRepository {
  GoalRepository(this._isar);
  final Isar _isar;

  Stream<List<Goal>> watchAll() {
    return _isar.goals
        .filter()
        .deletedAtIsNull()
        .sortBySortOrder()
        .watch(fireImmediately: true);
  }

  Future<int> save(Goal goal) {
    stampForSave(goal);
    return _isar.writeTxn(() => _isar.goals.put(goal));
  }

  /// Borrado lógico (tombstone) para que se propague en la sincronización.
  Future<void> delete(int id) {
    return _isar.writeTxn(() async {
      final g = await _isar.goals.get(id);
      if (g == null) return;
      stampForDelete(g);
      await _isar.goals.put(g);
    });
  }
}

final goalRepositoryProvider = Provider<GoalRepository>(
  (ref) => GoalRepository(ref.watch(isarProvider)),
);

final goalsProvider = StreamProvider<List<Goal>>(
  (ref) => ref.watch(goalRepositoryProvider).watchAll(),
);
