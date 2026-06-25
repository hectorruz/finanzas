import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../../core/db/isar_provider.dart';
import '../../core/market/yahoo_service.dart';
import '../models/holding.dart';

class HoldingRepository {
  HoldingRepository(this._isar);
  final Isar _isar;

  Stream<List<Holding>> watchAll() {
    return _isar.holdings
        .where()
        .sortByPurchaseDate()
        .watch(fireImmediately: true);
  }

  Future<List<Holding>> all() => _isar.holdings.where().findAll();

  Future<int> save(Holding holding) {
    return _isar.writeTxn(() => _isar.holdings.put(holding));
  }

  Future<void> delete(int id) {
    return _isar.writeTxn(() => _isar.holdings.delete(id));
  }
}

final holdingRepositoryProvider = Provider<HoldingRepository>(
  (ref) => HoldingRepository(ref.watch(isarProvider)),
);

final holdingsProvider = StreamProvider<List<Holding>>(
  (ref) => ref.watch(holdingRepositoryProvider).watchAll(),
);

/// Valoración de una posición: coste, valor de mercado actual (en EUR) y P/L.
class HoldingValuation {
  final Holding holding;
  final Quote quote;
  final double fxToEur;

  const HoldingValuation({
    required this.holding,
    required this.quote,
    required this.fxToEur,
  });

  /// Valor de mercado actual en céntimos de EUR.
  int get marketValueCents =>
      (quote.price * fxToEur * holding.quantity * 100).round();

  /// Coste de adquisición en céntimos de EUR.
  int get costCents => holding.costBasisCents;

  /// Beneficio/pérdida en céntimos de EUR.
  int get profitLossCents => marketValueCents - costCents;

  double get profitLossPercent {
    if (costCents == 0) return 0;
    return profitLossCents / costCents * 100;
  }
}

/// Valoración en vivo de una posición concreta (cotización + FX a EUR).
final holdingValuationProvider =
    FutureProvider.family<HoldingValuation, int>((ref, holdingId) async {
  final repo = ref.watch(holdingRepositoryProvider);
  final holdings = await repo.all();
  final holding = holdings.firstWhere((h) => h.id == holdingId);

  final yahoo = ref.watch(yahooServiceProvider);
  final quote = await yahoo.fetchQuote(holding.ticker);
  final fx = quote.currency.toUpperCase() == 'EUR'
      ? 1.0
      : await yahoo.fetchFxRate(quote.currency, 'EUR');

  return HoldingValuation(holding: holding, quote: quote, fxToEur: fx);
});

/// Resumen de cartera: total invertido y valor actual (ambos en céntimos EUR).
final portfolioSummaryProvider =
    FutureProvider<({int investedCents, int marketCents, int plCents})>(
        (ref) async {
  final repo = ref.watch(holdingRepositoryProvider);
  final yahoo = ref.watch(yahooServiceProvider);
  final holdings = await repo.all();

  var invested = 0;
  var market = 0;
  for (final h in holdings.where((h) => h.isOpen)) {
    invested += h.costBasisCents;
    final quote = await yahoo.fetchQuote(h.ticker);
    final fx = quote.currency.toUpperCase() == 'EUR'
        ? 1.0
        : await yahoo.fetchFxRate(quote.currency, 'EUR');
    market += (quote.price * fx * h.quantity * 100).round();
  }
  return (
    investedCents: invested,
    marketCents: market,
    plCents: market - invested,
  );
});
