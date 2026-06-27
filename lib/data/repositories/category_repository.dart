import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../../core/db/isar_provider.dart';
import '../models/category.dart';
import '../models/enums.dart';

class CategoryRepository {
  CategoryRepository(this._isar);
  final Isar _isar;

  Stream<List<Category>> watchAll() {
    return _isar.categories
        .where()
        .sortBySortOrder()
        .watch(fireImmediately: true);
  }

  Future<List<Category>> byKind(CategoryKind kind) {
    return _isar.categories
        .filter()
        .kindEqualTo(kind)
        .sortBySortOrder()
        .findAll();
  }

  Future<Category?> getById(int id) => _isar.categories.get(id);

  Future<int> save(Category category) {
    return _isar.writeTxn(() => _isar.categories.put(category));
  }

  /// Borra una categoría. Si tenía subcategorías, estas pasan a primer nivel
  /// (parentId = null) en lugar de quedar huérfanas.
  Future<void> delete(int id) {
    return _isar.writeTxn(() async {
      final children =
          await _isar.categories.filter().parentIdEqualTo(id).findAll();
      for (final c in children) {
        c.parentId = null;
      }
      if (children.isNotEmpty) await _isar.categories.putAll(children);
      await _isar.categories.delete(id);
    });
  }
}

/// Agrupa una lista de categorías en pares (padre, subcategorías) respetando el
/// orden de entrada. Las subcategorías cuyo padre no esté en la lista se tratan
/// como de primer nivel.
List<({Category parent, List<Category> children})> groupCategories(
    List<Category> all) {
  final byParent = <int, List<Category>>{};
  for (final c in all) {
    if (c.parentId != null) {
      byParent.putIfAbsent(c.parentId!, () => []).add(c);
    }
  }
  final ids = all.map((c) => c.id).toSet();
  final result = <({Category parent, List<Category> children})>[];
  for (final c in all) {
    if (c.parentId == null || !ids.contains(c.parentId)) {
      result.add((parent: c, children: byParent[c.id] ?? const []));
    }
  }
  return result;
}

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(ref.watch(isarProvider)),
);

final categoriesProvider = StreamProvider<List<Category>>(
  (ref) => ref.watch(categoryRepositoryProvider).watchAll(),
);
