import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account.dart';
import '../models/category.dart';
import 'account_repository.dart';
import 'category_repository.dart';

/// Mapa id -> cuenta (reactivo) para resolver nombres/iconos en listados.
final accountsByIdProvider = Provider<Map<int, Account>>((ref) {
  final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
  return {for (final a in accounts) a.id: a};
});

/// Mapa id -> categoría (reactivo).
final categoriesByIdProvider = Provider<Map<int, Category>>((ref) {
  final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
  return {for (final c in categories) c.id: c};
});
