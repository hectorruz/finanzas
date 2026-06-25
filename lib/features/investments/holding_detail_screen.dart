import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/money/money.dart';
import '../../core/router/app_router.dart';
import '../../data/repositories/holding_repository.dart';
import '../../shared/widgets/async_value_view.dart';

class HoldingDetailScreen extends ConsumerWidget {
  const HoldingDetailScreen({super.key, required this.holdingId});
  final int holdingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final valuation = ref.watch(holdingValuationProvider(holdingId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de inversión'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () =>
                context.push(Routes.holdingEditor, extra: holdingId),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.invalidate(holdingValuationProvider(holdingId)),
          ),
        ],
      ),
      body: AsyncValueView(
        value: valuation,
        onRetry: () => ref.invalidate(holdingValuationProvider(holdingId)),
        data: (v) {
          final h = v.holding;
          final positive = v.profitLossCents >= 0;
          final scheme = Theme.of(context).colorScheme;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(h.name.isEmpty ? h.ticker : h.name,
                  style: Theme.of(context).textTheme.headlineSmall),
              Text(h.ticker,
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              Card(
                color: positive
                    ? Colors.green.withOpacity(0.12)
                    : scheme.errorContainer.withOpacity(0.4),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Beneficio / Pérdida'),
                      const SizedBox(height: 4),
                      Text(
                        '${Money(v.profitLossCents).formatSigned()} '
                        '(${positive ? '+' : ''}'
                        '${v.profitLossPercent.toStringAsFixed(2)}%)',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: positive
                                  ? Colors.green.shade700
                                  : scheme.error,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _row('Cotización actual',
                  '${v.quote.price.toStringAsFixed(2)} ${v.quote.currency}'),
              if (v.quote.currency.toUpperCase() != 'EUR')
                _row('Tipo de cambio a EUR',
                    v.fxToEur.toStringAsFixed(4)),
              _row('Cantidad', '${h.quantity}'),
              _row('Precio de compra (EUR)',
                  Money(h.buyPriceCents).format()),
              _row('Coste total', Money(v.costCents).format()),
              _row('Valor de mercado', Money(v.marketValueCents).format()),
              _row('Fecha de compra',
                  DateFormat('d MMM yyyy', 'es').format(h.purchaseDate)),
              if (h.sellPriceCents != null)
                _row('Precio de venta (EUR)',
                    Money(h.sellPriceCents!).format()),
            ],
          );
        },
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
