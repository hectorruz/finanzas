import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../../core/db/isar_provider.dart';
import '../models/goal.dart';

class GoalRepository {
  GoalRepository(this._isar);
  final Isar _isar;

  Stream<List<Goal>> watchAll() {
    return _isar.goals.where().sortBySortOrder().watch(fireImmediately: true);
  }

  Future<int> save(Goal goal) {
    return _isar.writeTxn(() => _isar.goals.put(goal));
  }

  Future<void> delete(int id) {
    return _isar.writeTxn(() => _isar.goals.delete(id));
  }
}

final goalRepositoryProvider = Provider<GoalRepository>(
  (ref) => GoalRepository(ref.watch(isarProvider)),
);

final goalsProvider = StreamProvider<List<Goal>>(
  (ref) => ref.watch(goalRepositoryProvider).watchAll(),
);
