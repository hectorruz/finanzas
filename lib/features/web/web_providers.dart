import 'dart:typed_data';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/enums.dart';
import 'web_api_client.dart';
import 'web_models.dart';

/// Cliente conectado (null hasta emparejar en la pantalla de conexión).
final webClientProvider = StateProvider<WebApiClient?>((ref) => null);

/// "Tick" para refrescar los datos tras una escritura. Increméntalo con
/// [bumpWebRefresh] para que todos los `FutureProvider` de datos recarguen.
final webRefreshProvider = StateProvider<int>((ref) => 0);

/// Fuerza un refresco de todos los datos descargados.
void bumpWebRefresh(WidgetRef ref) =>
    ref.read(webRefreshProvider.notifier).state++;

/// Modo privacidad (ocultar importes) — local a la sesión web, sembrado desde
/// los ajustes del móvil al conectar y alternable desde la barra superior.
final webHideAmountsProvider = StateProvider<bool>((ref) => false);

/// Override local del tema desde la barra superior. `null` = seguir el tema de
/// los ajustes del móvil (`SettingsDto.themeMode`).
final webThemeModeOverrideProvider = StateProvider<ThemeMode?>((ref) => null);

// ---------------------------------------------------------------------------
// Estado del filtro de movimientos
// ---------------------------------------------------------------------------

/// Estado del filtro/orden de la pantalla de movimientos (equivalente web de
/// `TransactionFilter`). Inmutable con `copyWith` (centinela para poner a null).
class WebTxFilter {
  const WebTxFilter({
    this.query = '',
    this.from,
    this.to,
    this.types = const {},
    this.accountIds = const {},
    this.categoryIds = const {},
    this.minCents,
    this.maxCents,
    this.sort = WebTxSort.dateDesc,
  });

  final String query;
  final DateTime? from;
  final DateTime? to;
  final Set<TransactionType> types;
  final Set<int> accountIds;
  final Set<int> categoryIds;
  final int? minCents;
  final int? maxCents;
  final WebTxSort sort;

  /// Filtros "de contenido" activos (ignora orden y búsqueda de texto), para
  /// pintar el chip de "filtros activos".
  int get activeCount =>
      (from != null || to != null ? 1 : 0) +
      (types.isEmpty ? 0 : 1) +
      (accountIds.isEmpty ? 0 : 1) +
      (categoryIds.isEmpty ? 0 : 1) +
      (minCents != null || maxCents != null ? 1 : 0);

  bool get hasContentFilters => activeCount > 0;

  static const Object _keep = Object();

  WebTxFilter copyWith({
    String? query,
    Object? from = _keep,
    Object? to = _keep,
    Set<TransactionType>? types,
    Set<int>? accountIds,
    Set<int>? categoryIds,
    Object? minCents = _keep,
    Object? maxCents = _keep,
    WebTxSort? sort,
  }) {
    return WebTxFilter(
      query: query ?? this.query,
      from: from == _keep ? this.from : from as DateTime?,
      to: to == _keep ? this.to : to as DateTime?,
      types: types ?? this.types,
      accountIds: accountIds ?? this.accountIds,
      categoryIds: categoryIds ?? this.categoryIds,
      minCents: minCents == _keep ? this.minCents : minCents as int?,
      maxCents: maxCents == _keep ? this.maxCents : maxCents as int?,
      sort: sort ?? this.sort,
    );
  }

  /// Mantiene el texto de búsqueda y el orden, limpia el resto de filtros.
  WebTxFilter cleared() => WebTxFilter(query: query, sort: sort);
}

/// Filtro/orden actual de la pantalla de movimientos.
final webTxFilterProvider =
    StateProvider<WebTxFilter>((ref) => const WebTxFilter());

// ---------------------------------------------------------------------------
// Datos descargados del móvil
// ---------------------------------------------------------------------------

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
  final f = ref.watch(webTxFilterProvider);
  return client.transactions(
    from: f.from,
    to: f.to,
    query: f.query,
    types: f.types,
    accountIds: f.accountIds,
    categoryIds: f.categoryIds,
    minCents: f.minCents,
    maxCents: f.maxCents,
    sort: f.sort,
  );
});

/// Todos los movimientos sin filtrar — base de la analítica del dashboard e
/// informes, que re-filtra en cliente sin round-trips.
final webAllTransactionsProvider =
    FutureProvider.autoDispose<List<TransactionDto>>((ref) {
  ref.watch(webRefreshProvider);
  final client = ref.watch(webClientProvider);
  if (client == null) return Future.value(const []);
  return client.transactions();
});

final webRecurringProvider =
    FutureProvider.autoDispose<List<RecurringDto>>((ref) {
  ref.watch(webRefreshProvider);
  final client = ref.watch(webClientProvider);
  if (client == null) return Future.value(const []);
  return client.recurring();
});

final webGoalsProvider = FutureProvider.autoDispose<List<GoalDto>>((ref) {
  ref.watch(webRefreshProvider);
  final client = ref.watch(webClientProvider);
  if (client == null) return Future.value(const []);
  return client.goals();
});

final webReceiptsProvider = FutureProvider.autoDispose<List<ReceiptDto>>((ref) {
  ref.watch(webRefreshProvider);
  final client = ref.watch(webClientProvider);
  if (client == null) return Future.value(const []);
  return client.receipts();
});

/// Bytes de la imagen de un ticket (cacheados por id mientras se muestra).
final webReceiptImageProvider =
    FutureProvider.autoDispose.family<Uint8List, int>((ref, id) {
  ref.watch(webRefreshProvider);
  final client = ref.watch(webClientProvider);
  if (client == null) return Future.value(Uint8List(0));
  return client.receiptImage(id);
});

final webSettingsProvider = FutureProvider.autoDispose<SettingsDto>((ref) {
  ref.watch(webRefreshProvider);
  final client = ref.watch(webClientProvider);
  if (client == null) return Future.value(SettingsDto());
  return client.getSettings();
});

// ---------------------------------------------------------------------------
// Derivados: mapas por id y árboles aplanados
// ---------------------------------------------------------------------------

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

/// Cuentas en orden de árbol (padres antes que hijos, con profundidad).
final webAccountTreeProvider =
    Provider.autoDispose<List<WebTreeRow<AccountDto>>>((ref) {
  final accounts = ref.watch(webAccountsProvider).valueOrNull ?? const [];
  return buildWebTree(accounts);
});

/// Categorías de gasto en orden de árbol.
final webExpenseCategoryTreeProvider =
    Provider.autoDispose<List<WebTreeRow<CategoryDto>>>((ref) {
  final cats = ref.watch(webCategoriesProvider).valueOrNull ?? const [];
  return buildWebTree(
      cats.where((c) => c.kind == CategoryKind.expense).toList());
});

/// Categorías de ingreso en orden de árbol.
final webIncomeCategoryTreeProvider =
    Provider.autoDispose<List<WebTreeRow<CategoryDto>>>((ref) {
  final cats = ref.watch(webCategoriesProvider).valueOrNull ?? const [];
  return buildWebTree(
      cats.where((c) => c.kind == CategoryKind.income).toList());
});
