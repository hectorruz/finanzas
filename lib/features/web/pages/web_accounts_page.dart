import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/models/enums.dart';
import '../dialogs/web_account_dialog.dart';
import '../web_models.dart';
import '../web_providers.dart';
import '../widgets/web_money_text.dart';
import '../widgets/web_pickers.dart';
import '../widgets/web_ui.dart';

/// Cuentas con saldos en vivo, árbol de subcuentas, CRUD y panel de detalle con
/// los movimientos de la cuenta seleccionada.
class WebAccountsPage extends ConsumerStatefulWidget {
  const WebAccountsPage({super.key});

  @override
  ConsumerState<WebAccountsPage> createState() => _WebAccountsPageState();
}

class _WebAccountsPageState extends ConsumerState<WebAccountsPage> {
  int? _selectedId;

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(webAccountsProvider);
    final tree = ref.watch(webAccountTreeProvider);

    return WebPage(
      title: 'Cuentas',
      actions: [
        IconButton(
          tooltip: 'Refrescar',
          icon: const Icon(Icons.refresh),
          onPressed: () => bumpWebRefresh(ref),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Nueva cuenta'),
          onPressed: () =>
              showDialog(context: context, builder: (_) => const WebAccountDialog()),
        ),
      ],
      child: accountsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(48),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Text('Error: $e'),
        data: (accounts) {
          if (accounts.isEmpty) {
            return WebEmptyState(
              icon: Icons.account_balance_outlined,
              title: 'Sin cuentas',
              message: 'Crea tu primera cuenta.',
              action: FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Nueva cuenta'),
                onPressed: () => showDialog(
                    context: context, builder: (_) => const WebAccountDialog()),
              ),
            );
          }
          final total = accounts
              .where((a) => a.includeInTotal && !a.archived)
              .fold<int>(0, (s, a) => s + a.balanceCents);

          final list = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WebKpiCard(
                label: 'Balance total',
                icon: Icons.account_balance_wallet_outlined,
                value: WebMoneyText(total),
              ),
              const SizedBox(height: 16),
              WebCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    for (final row in tree)
                      _AccountRow(
                        row: row,
                        selected: row.item.id == _selectedId,
                        onTap: () =>
                            setState(() => _selectedId = row.item.id),
                        onEdit: () => showDialog(
                            context: context,
                            builder: (_) =>
                                WebAccountDialog(existing: row.item)),
                        onAddSub: () => showDialog(
                            context: context,
                            builder: (_) =>
                                WebAccountDialog(parentId: row.item.id)),
                      ),
                  ],
                ),
              ),
            ],
          );

          return LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1000;
            AccountDto? selected;
            if (_selectedId != null) {
              for (final a in accounts) {
                if (a.id == _selectedId) {
                  selected = a;
                  break;
                }
              }
            }
            if (wide && selected != null) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: list),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 380,
                    child: _AccountDetail(
                      account: selected,
                      onClose: () => setState(() => _selectedId = null),
                    ),
                  ),
                ],
              );
            }
            return list;
          });
        },
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.row,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    required this.onAddSub,
  });
  final WebTreeRow<AccountDto> row;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onAddSub;

  @override
  Widget build(BuildContext context) {
    final a = row.item;
    return Padding(
      padding: EdgeInsets.only(left: 8.0 + row.depth * 24, right: 8),
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.secondaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          onTap: onTap,
          leading: WebColorDot(
            colorValue: a.colorValue,
            icon: webIconFor(a.iconName, fallback: Icons.account_balance),
          ),
          title: Text(a.name),
          subtitle: a.archived
              ? const Text('Archivada')
              : (a.note.isEmpty ? null : Text(a.note)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              WebMoneyText(a.balanceCents,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              PopupMenuButton<String>(
                onSelected: (v) => v == 'edit' ? onEdit() : onAddSub(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Editar')),
                  PopupMenuItem(value: 'sub', child: Text('Añadir subcuenta')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountDetail extends ConsumerWidget {
  const _AccountDetail({required this.account, required this.onClose});
  final AccountDto account;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(webAllTransactionsProvider).valueOrNull ?? const [];
    final categories = ref.watch(webCategoriesByIdProvider);
    final movements = all
        .where((t) =>
            t.accountId == account.id || t.toAccountId == account.id)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              WebColorDot(
                colorValue: account.colorValue,
                icon: webIconFor(account.iconName,
                    fallback: Icons.account_balance),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(account.name,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: onClose),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: WebMoneyText(account.balanceCents,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Editar cuenta'),
              onPressed: () => showDialog(
                  context: context,
                  builder: (_) => WebAccountDialog(existing: account)),
            ),
          ),
          const Divider(height: 24),
          Text('Movimientos (${movements.length})',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          if (movements.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Sin movimientos en esta cuenta.'),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final t in movements.take(50))
                    _movementTile(context, t, categories),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _movementTile(
      BuildContext context, TransactionDto t, Map<int, CategoryDto> categories) {
    final scheme = Theme.of(context).colorScheme;
    // Signo relativo a ESTA cuenta (en transferencias, salida si es origen).
    final isTransfer = t.type == TransactionType.transfer;
    int effect;
    if (isTransfer) {
      effect = t.accountId == account.id ? -t.amountCents : t.amountCents;
    } else {
      effect = t.type == TransactionType.income ? t.amountCents : -t.amountCents;
    }
    final cat = t.categoryId != null ? categories[t.categoryId] : null;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: WebColorDot(
        size: 30,
        colorValue: cat?.colorValue ?? 0xFF9E9E9E,
        icon: isTransfer ? Icons.swap_horiz : webIconFor(cat?.iconName ?? 'category'),
      ),
      title: Text(t.concept.isEmpty ? (cat?.name ?? 'Movimiento') : t.concept,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(DateFormat('dd/MM/yyyy').format(t.date)),
      trailing: WebMoneyText(
        effect,
        signed: true,
        color: effect >= 0 ? Colors.green : scheme.error,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}
