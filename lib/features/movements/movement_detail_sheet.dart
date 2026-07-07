import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/icons/app_icons.dart';
import '../../core/router/app_router.dart';
import '../../data/models/enums.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/lookups.dart';
import '../../data/repositories/receipt_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../shared/widgets/delete_confirm_dialog.dart';
import '../../shared/widgets/detail_sheet.dart';
import '../../shared/widgets/money_text.dart';

/// Abre el panel de detalles de un movimiento.
Future<void> showMovementDetailSheet(BuildContext context, int transactionId) {
  return showDetailSheet<void>(
    context,
    builder: (controller) => _MovementDetailView(
      transactionId: transactionId,
      controller: controller,
    ),
  );
}

class _MovementDetailView extends ConsumerWidget {
  const _MovementDetailView({
    required this.transactionId,
    required this.controller,
  });

  final int transactionId;
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(transactionByIdProvider(transactionId));
    final categories = ref.watch(categoriesByIdProvider);
    final accounts = ref.watch(accountsByIdProvider);
    final scheme = Theme.of(context).colorScheme;

    final txn = async.valueOrNull;
    if (txn == null) {
      return ListView(
        controller: controller,
        children: [
          const SizedBox(height: 48),
          Center(
            child: async.isLoading
                ? const CircularProgressIndicator()
                : const Text('El movimiento ya no existe'),
          ),
        ],
      );
    }

    final category = txn.categoryId != null ? categories[txn.categoryId] : null;
    final account = accounts[txn.accountId];
    final toAccount =
        txn.toAccountId != null ? accounts[txn.toAccountId] : null;

    final isExpense = txn.type == TransactionType.expense;
    final isTransfer = txn.type == TransactionType.transfer;
    final color = isTransfer
        ? scheme.tertiary
        : isExpense
            ? scheme.error
            : Colors.green.shade600;
    final accentInt = category?.colorValue ?? color.value;
    final icon = isTransfer
        ? Icons.swap_horiz
        : category != null
            ? iconByName(category.iconName)
            : (isExpense ? Icons.arrow_downward : Icons.arrow_upward);
    final amountPrefix = isTransfer ? '' : (isExpense ? '-' : '+');
    final typeLabel = isTransfer
        ? 'Transferencia'
        : isExpense
            ? 'Gasto'
            : 'Ingreso';

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: Color(accentInt).withOpacity(0.18),
              child: Icon(icon, color: Color(accentInt), size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    txn.concept.isEmpty
                        ? (category?.name ?? 'Movimiento')
                        : txn.concept,
                    style: Theme.of(context).textTheme.titleLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    typeLabel,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Editar',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () =>
                  context.push(Routes.movementEditor, extra: txn.id),
            ),
          ],
        ),
        const SizedBox(height: 12),
        MoneyText(
          txn.amountCents,
          prefix: amountPrefix,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
        ),
        const Divider(height: 32),
        if (category != null)
          DetailRow(
            icon: Icons.category_outlined,
            label: 'Categoría',
            value: categoryFullName(txn.categoryId, categories,
                fallback: category.name),
          ),
        if (account != null)
          DetailRow(
            icon: Icons.account_balance_wallet_outlined,
            label: isTransfer ? 'Cuenta origen' : 'Cuenta',
            value: account.name,
          ),
        if (isTransfer && toAccount != null)
          DetailRow(
            icon: Icons.south_east,
            label: 'Cuenta destino',
            value: toAccount.name,
          ),
        DetailRow(
          icon: Icons.calendar_today_outlined,
          label: 'Fecha',
          value: DateFormat('d MMM yyyy', 'es').format(txn.date),
        ),
        if (txn.note.isNotEmpty)
          DetailRow(
            icon: Icons.sticky_note_2_outlined,
            label: 'Nota',
            value: txn.note,
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => _delete(context, ref, txn),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Eliminar movimiento'),
          style: OutlinedButton.styleFrom(
            foregroundColor: scheme.error,
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    TransactionModel txn,
  ) async {
    final hasReceipt = txn.receiptId != null;
    final result = await showDeleteConfirm(
      context,
      title: 'Eliminar movimiento',
      message: '¿Eliminar este movimiento?',
      hasLinked: hasReceipt,
      linkedLabel: 'Borrar también el ticket vinculado',
    );
    if (result == null || !result.confirmed) return;
    await ref.read(transactionRepositoryProvider).delete(txn.id);
    if (result.alsoDeleteLinked && txn.receiptId != null) {
      await ref.read(receiptRepositoryProvider).delete(txn.receiptId!);
    }
    if (context.mounted) Navigator.of(context).pop();
  }
}
