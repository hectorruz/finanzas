import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/money/money.dart';
import '../../core/router/app_router.dart';
import '../../data/models/receipt.dart';
import '../../data/repositories/receipt_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../shared/widgets/async_value_view.dart';
import '../../shared/widgets/delete_confirm_dialog.dart';
import 'receipt_detail_sheet.dart';
import 'receipt_image_store.dart';

class ReceiptsScreen extends ConsumerStatefulWidget {
  const ReceiptsScreen({super.key});

  @override
  ConsumerState<ReceiptsScreen> createState() => _ReceiptsScreenState();
}

class _ReceiptsScreenState extends ConsumerState<ReceiptsScreen> {
  final Set<int> _selected = {};
  bool get _selecting => _selected.isNotEmpty;

  void _clearSelection() => setState(_selected.clear);

  void _toggle(int id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final receipts = ref.watch(receiptsProvider);
    return Scaffold(
      appBar: _selecting
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
              ),
              title: Text('${_selected.length} seleccionados'),
              actions: [
                IconButton(
                  tooltip: 'Eliminar',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _bulkDelete,
                ),
              ],
            )
          : AppBar(title: const Text('Tickets')),
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton.extended(
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
              for (final r in list) _ReceiptTile(
                receipt: r,
                selected: _selected.contains(r.id),
                onTap: () {
                  if (_selecting) {
                    _toggle(r.id);
                  } else {
                    showReceiptDetailSheet(context, r.id);
                  }
                },
                onLongPress: () => _toggle(r.id),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _bulkDelete() async {
    final all = ref.read(receiptsProvider).valueOrNull ?? const <Receipt>[];
    final selected = all.where((r) => _selected.contains(r.id)).toList();
    if (selected.isEmpty) return;
    final hasLinked = selected.any((r) => r.transactionId != null);
    final result = await showDeleteConfirm(
      context,
      title: 'Eliminar tickets',
      message: '¿Eliminar ${selected.length} tickets?',
      hasLinked: hasLinked,
      linkedLabel: 'Borrar también los gastos vinculados',
    );
    if (result == null || !result.confirmed) return;

    await ref
        .read(receiptRepositoryProvider)
        .deleteMany(selected.map((r) => r.id).toList());
    for (final r in selected) {
      await deleteReceiptImage(r.imagePath);
    }
    if (result.alsoDeleteLinked) {
      final txnIds = selected
          .map((r) => r.transactionId)
          .whereType<int>()
          .toList();
      if (txnIds.isNotEmpty) {
        await ref.read(transactionRepositoryProvider).deleteMany(txnIds);
      }
    }
    _clearSelection();
  }
}

class _ReceiptTile extends StatelessWidget {
  const _ReceiptTile({
    required this.receipt,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final Receipt receipt;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasImage =
        receipt.imagePath.isNotEmpty && File(receipt.imagePath).existsSync();
    return ListTile(
      selected: selected,
      selectedTileColor: scheme.primaryContainer.withOpacity(0.4),
      leading: selected
          ? CircleAvatar(
              backgroundColor: scheme.primary,
              child: Icon(Icons.check, color: scheme.onPrimary),
            )
          : hasImage
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(receipt.imagePath),
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                )
              : const CircleAvatar(child: Icon(Icons.receipt_long)),
      title: Text(receipt.merchant.isEmpty ? 'Ticket' : receipt.merchant),
      subtitle: Text(DateFormat('d MMM yyyy', 'es').format(receipt.date)),
      trailing: Text(
        Money(receipt.totalCents).format(),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      onTap: onTap,
      onLongPress: onLongPress,
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
