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

  Future<void> delete(int id) {
    return _isar.writeTxn(() => _isar.categories.delete(id));
  }
}

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(ref.watch(isarProvider)),
);

final categoriesProvider = StreamProvider<List<Category>>(
  (ref) => ref.watch(categoryRepositoryProvider).watchAll(),
);
