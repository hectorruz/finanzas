import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/money/money.dart';
import '../../core/router/app_router.dart';
import '../../data/repositories/receipt_repository.dart';
import '../../shared/widgets/async_value_view.dart';

class ReceiptsScreen extends ConsumerWidget {
  const ReceiptsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipts = ref.watch(receiptsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Tickets')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.receiptScan),
        icon: const Icon(Icons.document_scanner),
        label: const Text('Escanear'),
      ),
      body: AsyncValueView(
        value: receipts,
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Escanea tus tickets para llevar el control de dónde compras '
                  'y en qué gastas más.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              const _MerchantStats(),
              const Divider(),
              for (final r in list)
                ListTile(
                  leading: r.imagePath.isNotEmpty &&
                          File(r.imagePath).existsSync()
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(r.imagePath),
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          ),
                        )
                      : const CircleAvatar(child: Icon(Icons.receipt_long)),
                  title: Text(
                      r.merchant.isEmpty ? 'Ticket' : r.merchant),
                  subtitle: Text(
                      DateFormat('d MMM yyyy', 'es').format(r.date)),
                  trailing: Text(
                    Money(r.totalCents).format(),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MerchantStats extends ConsumerWidget {
  const _MerchantStats();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(merchantStatsProvider);
    return AsyncValueView(
      value: stats,
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        final top = list.take(5).toList();
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Dónde más compras',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final s in top)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text('${s.merchant} (${s.count})')),
                      Text(Money(s.totalCents).format(),
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
