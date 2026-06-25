import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money/money.dart';
import '../../core/router/app_router.dart';
import '../../data/repositories/holding_repository.dart';
import '../../shared/widgets/async_value_view.dart';

class InvestmentsScreen extends ConsumerWidget {
  const InvestmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holdings = ref.watch(holdingsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inversiones'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(portfolioSummaryProvider);
              ref.invalidate(holdingValuationProvider);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.holdingEditor),
        icon: const Icon(Icons.add),
        label: const Text('Añadir'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(portfolioSummaryProvider);
          ref.invalidate(holdingValuationProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          children: [
            const _PortfolioSummary(),
            const SizedBox(height: 8),
            AsyncValueView(
              value: holdings,
              data: (list) {
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Añade acciones o ETFs por su ticker (p. ej. AAPL, '
                      'VWCE.DE) para seguir tu cartera en tiempo real.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final h in list)
                      Card(
                        child: ListTile(
                          title: Text(
                            h.name.isEmpty ? h.ticker : h.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                              '${h.ticker} · ${h.quantity} uds.'),
                          trailing: _HoldingTrailing(holdingId: h.id),
                          onTap: () => context.push(
                            Routes.holdingDetail,
                            extra: h.id,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PortfolioSummary extends ConsumerWidget {
  const _PortfolioSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(portfolioSummaryProvider);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: AsyncValueView(
          value: summary,
          onRetry: () => ref.invalidate(portfolioSummaryProvider),
          data: (s) {
            final positive = s.plCents >= 0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Valor actual de la cartera',
                    style: TextStyle(color: scheme.onPrimaryContainer)),
                const SizedBox(height: 6),
                Text(
                  Money(s.marketCents).format(),
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Invertido',
                        style:
                            TextStyle(color: scheme.onPrimaryContainer)),
                    Text(Money(s.investedCents).format(),
                        style:
                            TextStyle(color: scheme.onPrimaryContainer)),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Beneficio / Pérdida',
                        style:
                            TextStyle(color: scheme.onPrimaryContainer)),
                    Text(
                      Money(s.plCents).formatSigned(),
                      style: TextStyle(
                        color: positive
                            ? Colors.green.shade700
                            : scheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HoldingTrailing extends ConsumerWidget {
  const _HoldingTrailing({required this.holdingId});
  final int holdingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final valuation = ref.watch(holdingValuationProvider(holdingId));
    return valuation.when(
      loading: () => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, __) => const Icon(Icons.cloud_off, size: 18),
      data: (v) {
        final positive = v.profitLossCents >= 0;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(Money(v.marketValueCents).format(),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              '${positive ? '+' : ''}'
              '${v.profitLossPercent.toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 12,
                color: positive
                    ? Colors.green.shade600
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        );
      },
    );
  }
}
