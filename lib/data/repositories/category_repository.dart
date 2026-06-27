import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../../core/db/isar_provider.dart';
import '../models/category.dart';
import '../models/enums.dart';
import 'tree.dart';

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

  /// Borra una categoría. Sus subcategorías directas se recolocan bajo el
  /// padre de la borrada (su "abuelo"), conservando el resto del árbol en lugar
  /// de quedar huérfanas.
  Future<void> delete(int id) {
    return _isar.writeTxn(() async {
      final deleted = await _isar.categories.get(id);
      final children =
          await _isar.categories.filter().parentIdEqualTo(id).findAll();
      for (final c in children) {
        c.parentId = deleted?.parentId;
      }
      if (children.isNotEmpty) await _isar.categories.putAll(children);
      await _isar.categories.delete(id);
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
