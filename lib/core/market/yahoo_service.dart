import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Cotización devuelta por Yahoo Finance.
class Quote {
  final String ticker;
  final double price;
  final String currency;
  final double? previousClose;
  final String? shortName;

  const Quote({
    required this.ticker,
    required this.price,
    required this.currency,
    this.previousClose,
    this.shortName,
  });

  /// Variación porcentual respecto al cierre anterior, si está disponible.
  double? get changePercent {
    if (previousClose == null || previousClose == 0) return null;
    return (price - previousClose!) / previousClose! * 100;
  }
}

/// Cliente real (sin mocks) de la API pública de Yahoo Finance.
///
/// Endpoint: `https://query1.finance.yahoo.com/v8/finance/chart/<TICKER>`.
/// La conversión de divisas usa los pares FX de Yahoo (p. ej. `USDEUR=X`).
class YahooService {
  YahooService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _base = 'https://query1.finance.yahoo.com/v8/finance/chart';
  static const _timeout = Duration(seconds: 12);

  Future<Quote> fetchQuote(String ticker) async {
    final symbol = ticker.trim().toUpperCase();
    final uri = Uri.parse('$_base/$symbol');

    final res = await _client.get(
      uri,
      // Yahoo rechaza peticiones sin User-Agent de navegador.
      headers: const {'User-Agent': 'Mozilla/5.0 (compatible; Finanzas/1.0)'},
    ).timeout(_timeout);

    if (res.statusCode != 200) {
      throw YahooException(
        'Error HTTP ${res.statusCode} al consultar $symbol',
      );
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final chart = json['chart'] as Map<String, dynamic>?;
    final error = chart?['error'];
    if (error != null) {
      throw YahooException('Yahoo devolvió error para $symbol: $error');
    }

    final results = chart?['result'] as List<dynamic>?;
    if (results == null || results.isEmpty) {
      throw YahooException('Sin datos para el ticker $symbol');
    }

    final meta = (results.first as Map<String, dynamic>)['meta']
        as Map<String, dynamic>?;
    if (meta == null) {
      throw YahooException('Respuesta inesperada para $symbol');
    }

    final price = (meta['regularMarketPrice'] as num?)?.toDouble();
    if (price == null) {
      throw YahooException('Sin precio de mercado para $symbol');
    }

    return Quote(
      ticker: symbol,
      price: price,
      currency: (meta['currency'] as String?) ?? 'USD',
      previousClose: (meta['chartPreviousClose'] as num?)?.toDouble() ??
          (meta['previousClose'] as num?)?.toDouble(),
      shortName: meta['shortName'] as String? ?? meta['symbol'] as String?,
    );
  }

  /// Tipo de cambio de [from] a [to] (p. ej. USD -> EUR). Devuelve 1.0 si son
  /// la misma divisa.
  Future<double> fetchFxRate(String from, String to) async {
    final f = from.trim().toUpperCase();
    final t = to.trim().toUpperCase();
    if (f == t) return 1.0;
    final quote = await fetchQuote('$f$t=X');
    return quote.price;
  }

  void dispose() => _client.close();
}

class YahooException implements Exception {
  YahooException(this.message);
  final String message;
  @override
  String toString() => message;
}

final yahooServiceProvider = Provider<YahooService>((ref) {
  final service = YahooService();
  ref.onDispose(service.dispose);
  return service;
});

/// Cotización en vivo de un ticker (auto-disposed). La UI la observa por ticker.
final quoteProvider = FutureProvider.family<Quote, String>((ref, ticker) {
  return ref.watch(yahooServiceProvider).fetchQuote(ticker);
});

/// Tipo de cambio cacheado a EUR para una divisa dada.
final fxToEurProvider = FutureProvider.family<double, String>((ref, currency) {
  return ref.watch(yahooServiceProvider).fetchFxRate(currency, 'EUR');
});
