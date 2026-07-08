import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'web_api_client.dart';
import 'web_models.dart';

/// Cliente conectado (null hasta emparejar en la pantalla de conexión).
final webClientProvider = StateProvider<WebApiClient?>((ref) => null);

/// "Tick" para refrescar los datos tras una escritura.
final webRefreshProvider = StateProvider<int>((ref) => 0);

/// Texto de búsqueda de movimientos.
final webTxQueryProvider = StateProvider<String>((ref) => '');

final webAccountsProvider = FutureProvider.autoDispose<List<AccountDto>>((ref) {
  ref.watch(webRefreshProvider);
  final client = ref.watch(webClientProvider);
  if (client == null) return Future.value(const []);
  return client.accounts();
});

final webCategoriesProvider =
    FutureProvider.autoDispose<List<CategoryDto>>((ref) {
  ref.watch(webRefreshProvider);
  final client = ref.watch(webClientProvider);
  if (client == null) return Future.value(const []);
  return client.categories();
});

final webTransactionsProvider =
    FutureProvider.autoDispose<List<TransactionDto>>((ref) {
  ref.watch(webRefreshProvider);
  final client = ref.watch(webClientProvider);
  if (client == null) return Future.value(const []);
  return client.transactions(query: ref.watch(webTxQueryProvider));
});

final webAccountsByIdProvider =
    Provider.autoDispose<Map<int, AccountDto>>((ref) {
  final accounts = ref.watch(webAccountsProvider).valueOrNull ?? const [];
  return {for (final a in accounts) a.id: a};
});

final webCategoriesByIdProvider =
    Provider.autoDispose<Map<int, CategoryDto>>((ref) {
  final categories = ref.watch(webCategoriesProvider).valueOrNull ?? const [];
  return {for (final c in categories) c.id: c};
});
