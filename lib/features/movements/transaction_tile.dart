import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/icons/app_icons.dart';
import '../../data/models/enums.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/lookups.dart';
import '../../shared/widgets/money_text.dart';

/// Fila reutilizable que representa un movimiento.
class TransactionTile extends ConsumerWidget {
  const TransactionTile({
    super.key,
    required this.txn,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.dense = false,
  });

  final TransactionModel txn;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final categories = ref.watch(categoriesByIdProvider);
    final accounts = ref.watch(accountsByIdProvider);

    final category =
        txn.categoryId != null ? categories[txn.categoryId] : null;
    final account = accounts[txn.accountId];

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

    final subtitleParts = <String>[
      if (category != null) category.name,
      if (account != null) account.name,
      DateFormat('d MMM', 'es').format(txn.date),
    ];

    return ListTile(
      selected: selected,
      selectedTileColor: scheme.primaryContainer.withOpacity(0.4),
      dense: dense,
      leading: CircleAvatar(
        backgroundColor: selected
            ? scheme.primary
            : Color(accentInt).withOpacity(0.18),
        child: Icon(
          selected ? Icons.check : icon,
          color: selected ? scheme.onPrimary : Color(accentInt),
        ),
      ),
      title: Text(
        txn.concept.isEmpty ? (category?.name ?? 'Movimiento') : txn.concept,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitleParts.join(' · ')),
      trailing: MoneyText(
        txn.amountCents,
        prefix: amountPrefix,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
