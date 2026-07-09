import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/icons/app_icons.dart';
import '../../core/router/app_router.dart';
import '../../data/models/receipt.dart';
import '../../data/repositories/lookups.dart';
import '../../data/repositories/receipt_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../shared/widgets/delete_confirm_dialog.dart';
import '../../shared/widgets/detail_sheet.dart';
import '../../shared/widgets/money_text.dart';
import 'receipt_image_store.dart';

/// Abre el panel de detalles de un ticket.
Future<void> showReceiptDetailSheet(BuildContext context, int receiptId) {
  return showDetailSheet<void>(
    context,
    builder: (controller) => _ReceiptDetailView(
      receiptId: receiptId,
      controller: controller,
    ),
  );
}

class _ReceiptDetailView extends ConsumerWidget {
  const _ReceiptDetailView({
    required this.receiptId,
    required this.controller,
  });

  final int receiptId;
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(receiptByIdProvider(receiptId));
    final categories = ref.watch(categoriesByIdProvider);
    final accounts = ref.watch(accountsByIdProvider);
    final scheme = Theme.of(context).colorScheme;

    final receipt = async.valueOrNull;
    if (receipt == null) {
      return ListView(
        controller: controller,
        children: [
          const SizedBox(height: 48),
          Center(
            child: async.isLoading
                ? const CircularProgressIndicator()
                : const Text('El ticket ya no existe'),
          ),
        ],
      );
    }

    final category =
        receipt.categoryId != null ? categories[receipt.categoryId] : null;
    final account =
        receipt.accountId != null ? accounts[receipt.accountId] : null;
    final accentInt = category?.colorValue ?? scheme.primary.value;
    final hasImage =
        receipt.imagePath.isNotEmpty && File(receipt.imagePath).existsSync();

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Row(
          children: [
            if (hasImage)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(receipt.imagePath),
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                ),
              )
            else
              CircleAvatar(
                radius: 26,
                backgroundColor: Color(accentInt).withOpacity(0.18),
                child: Icon(
                  category != null
                      ? iconByName(category.iconName)
                      : Icons.receipt_long,
                  color: Color(accentInt),
                  size: 26,
                ),
              ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                receipt.merchant.isEmpty ? 'Ticket' : receipt.merchant,
                style: Theme.of(context).textTheme.titleLarge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: 'Editar',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () =>
                  context.push(Routes.receiptScan, extra: receipt.id),
            ),
          ],
        ),
        const SizedBox(height: 12),
        MoneyText(
          receipt.totalCents,
          prefix: '-',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: scheme.error,
                fontWeight: FontWeight.w700,
              ),
        ),
        const Divider(height: 32),
        if (hasImage) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(
              File(receipt.imagePath),
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 16),
        ],
        DetailRow(
          icon: Icons.category_outlined,
          label: 'Categoría',
          value:
              categoryFullName(receipt.categoryId, categories, fallback: 'Sin categoría'),
        ),
        DetailRow(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Cuenta',
          value: account?.name ?? 'Sin cuenta',
        ),
        DetailRow(
          icon: Icons.calendar_today_outlined,
          label: 'Fecha',
          value: DateFormat('d MMM yyyy', 'es').format(receipt.date),
        ),
        DetailRow(
          icon: Icons.receipt_long_outlined,
          label: 'Gasto vinculado',
          value: receipt.transactionId != null ? 'Sí' : 'No',
        ),
        if (hasImage) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _saveToGallery(context, receipt.imagePath),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Guardar en galería'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => _delete(context, ref, receipt),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Eliminar ticket'),
          style: OutlinedButton.styleFrom(
            foregroundColor: scheme.error,
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }

  Future<void> _saveToGallery(BuildContext context, String imagePath) async {
    final ok = await saveReceiptToGallery(imagePath);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Guardado en el álbum "$receiptsGalleryAlbum" de la galería'
              : 'No se pudo guardar en la galería',
        ),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Receipt receipt,
  ) async {
    final hasExpense = receipt.transactionId != null;
    final result = await showDeleteConfirm(
      context,
      title: 'Eliminar ticket',
      message: '¿Eliminar este ticket?',
      hasLinked: hasExpense,
      linkedLabel: 'Borrar también el gasto vinculado',
    );
    if (result == null || !result.confirmed) return;
    await ref.read(receiptRepositoryProvider).delete(receipt.id);
    await deleteReceiptImage(receipt.imagePath);
    if (result.alsoDeleteLinked && receipt.transactionId != null) {
      await ref.read(transactionRepositoryProvider).delete(receipt.transactionId!);
    }
    if (context.mounted) Navigator.of(context).pop();
  }
}
