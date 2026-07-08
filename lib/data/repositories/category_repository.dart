import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../../core/db/isar_provider.dart';
import '../../core/sync/sync_stamp.dart';
import '../models/category.dart';
import '../models/enums.dart';
import 'tree.dart';

class CategoryRepository {
  CategoryRepository(this._isar);
  final Isar _isar;

  Stream<List<Category>> watchAll() {
    return _isar.categories
        .filter()
        .deletedAtIsNull()
        .sortBySortOrder()
        .watch(fireImmediately: true);
  }

  Future<List<Category>> byKind(CategoryKind kind) {
    return _isar.categories
        .filter()
        .deletedAtIsNull()
        .kindEqualTo(kind)
        .sortBySortOrder()
        .findAll();
  }

  Future<Category?> getById(int id) => _isar.categories.get(id);

  Future<int> save(Category category) {
    stampForSave(category);
    return _isar.writeTxn(() => _isar.categories.put(category));
  }

  /// Borra (lógicamente) una categoría. Sus subcategorías directas se recolocan
  /// bajo el padre de la borrada (su "abuelo"), conservando el resto del árbol
  /// en lugar de quedar huérfanas. La categoría se marca como tombstone
  /// (`deletedAt`) para que el borrado se propague en la sincronización.
  Future<void> delete(int id) {
    return _isar.writeTxn(() async {
      final now = DateTime.now();
      final deleted = await _isar.categories.get(id);
      if (deleted == null) return;

      final children =
          await _isar.categories.filter().parentIdEqualTo(id).findAll();
      for (final c in children) {
        c.parentId = deleted.parentId;
        stampForSave(c, now: now); // el re-parenting es una modificación
      }
      if (children.isNotEmpty) await _isar.categories.putAll(children);

      stampForDelete(deleted, now: now);
      await _isar.categories.put(deleted);
    });
  }
}

/// Aplana las categorías en un árbol de anidamiento ilimitado (subcategorías
/// dentro de subcategorías), con la profundidad de cada nodo.
List<TreeEntry<Category>> flattenCategories(List<Category> all) => flattenTree(
      all,
      idOf: (c) => c.id,
      parentIdOf: (c) => c.parentId,
    );

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(ref.watch(isarProvider)),
);

final categoriesProvider = StreamProvider<List<Category>>(
  (ref) => ref.watch(categoryRepositoryProvider).watchAll(),
);
