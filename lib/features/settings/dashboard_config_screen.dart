import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/app_icons.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/enums.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/settings_repository.dart';

/// Permite activar/desactivar, reordenar las tarjetas del dashboard y elegir
/// qué cuentas suman en el balance total.
class DashboardConfigScreen extends ConsumerWidget {
  const DashboardConfigScreen({super.key});

  static const _labels = {
    DashboardCardType.totalBalance: 'Balance total',
    DashboardCardType.accountsBalance: 'Balance por cuentas',
    DashboardCardType.monthComparison: 'Comparativa mensual',
    DashboardCardType.recentMovements: 'Últimos movimientos',
    DashboardCardType.quickAdd: 'Añadir ingreso/gasto',
    DashboardCardType.scanReceipt: 'Escanear ticket',
    DashboardCardType.goals: 'Objetivos',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final repo = ref.read(settingsRepositoryProvider);
    final active = settings.cards;
    final inactive = DashboardCardType.values
        .where((c) => !active.contains(c))
        .toList();
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Personalizar inicio')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Tarjetas activas (mantén pulsado para reordenar)',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: true,
            onReorder: (oldIndex, newIndex) {
              final list = [...active];
              if (newIndex > oldIndex) newIndex--;
              final item = list.removeAt(oldIndex);
              list.insert(newIndex, item);
              repo.update((s) =>
                  s.dashboardCards = list.map((c) => c.name).toList());
            },
            children: [
              for (final card in active)
                ListTile(
                  key: ValueKey(card.name),
                  leading: const Icon(Icons.drag_handle),
                  title: Text(_labels[card] ?? card.name),
                  trailing: IconButton(
                    icon: const Icon(Icons.visibility_off),
                    onPressed: () => repo.update((s) => s.dashboardCards =
                        active.where((c) => c != card).map((c) => c.name).toList()),
                  ),
                ),
            ],
          ),
          if (inactive.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Tarjetas ocultas',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final card in inactive)
              ListTile(
                title: Text(_labels[card] ?? card.name),
                trailing: IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => repo.update((s) => s.dashboardCards =
                      [...active.map((c) => c.name), card.name]),
                ),
              ),
          ],
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Cuentas en la tarjeta "Balance por cuentas"',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Si no marcas ninguna, se muestran todas las cuentas activas.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          for (final a in accounts)
            CheckboxListTile(
              title: Text(a.name),
              value: settings.accountsCardIds.contains(a.id),
              onChanged: (checked) => repo.update((s) {
                final ids = [...s.accountsCardIds];
                if (checked ?? false) {
                  if (!ids.contains(a.id)) ids.add(a.id);
                } else {
                  ids.remove(a.id);
                }
                s.accountsCardIds = ids;
              }),
            ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Cuentas en el balance total',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Si no marcas ninguna, se usan todas las cuentas marcadas como '
              '"incluir en balance total".',
              style: TextStyle(fontSize: 12),
            ),
          ),
          for (final a in accounts)
            CheckboxListTile(
              title: Text(a.name),
              value: settings.totalBalanceAccountIds.contains(a.id),
              onChanged: (checked) => repo.update((s) {
                final ids = [...s.totalBalanceAccountIds];
                if (checked ?? false) {
                  if (!ids.contains(a.id)) ids.add(a.id);
                } else {
                  ids.remove(a.id);
                }
                s.totalBalanceAccountIds = ids;
              }),
            ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Subtotales del balance',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Totales adicionales que aparecen bajo el balance total, cada uno '
              'sumando las cuentas o subcuentas que elijas.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          for (final (i, st) in settings.subtotals.indexed)
            ListTile(
              leading: const Icon(Icons.functions),
              title: Text(st.name.isEmpty ? '(sin nombre)' : st.name),
              subtitle: Text(
                  '${st.accountIds.length} ${st.accountIds.length == 1 ? 'cuenta' : 'cuentas'}'),
              onTap: () => _editSubtotal(context, repo, index: i, initial: st),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Eliminar',
                onPressed: () => repo.update((s) {
                  final list = [...s.subtotals]..removeAt(i);
                  s.balanceSubtotals = list.map((e) => e.encode()).toList();
                }),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: OutlinedButton.icon(
              onPressed: () => _editSubtotal(context, repo),
              icon: const Icon(Icons.add),
              label: const Text('Añadir subtotal'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Abre el editor de subtotal; si [index] es null crea uno nuevo, si no lo
  /// reemplaza en esa posición.
  Future<void> _editSubtotal(
    BuildContext context,
    SettingsRepository repo, {
    int? index,
    BalanceSubtotal? initial,
  }) async {
    final result = await Navigator.of(context).push<BalanceSubtotal>(
      MaterialPageRoute(
        builder: (_) => _SubtotalEditorScreen(initial: initial),
      ),
    );
    if (result == null) return;
    await repo.update((s) {
      final list = [...s.subtotals];
      if (index == null) {
        list.add(result);
      } else {
        list[index] = result;
      }
      s.balanceSubtotals = list.map((e) => e.encode()).toList();
    });
  }
}

/// Editor de un subtotal del balance: nombre y cuentas/subcuentas que suma.
class _SubtotalEditorScreen extends ConsumerStatefulWidget {
  const _SubtotalEditorScreen({this.initial});

  final BalanceSubtotal? initial;

  @override
  ConsumerState<_SubtotalEditorScreen> createState() =>
      _SubtotalEditorScreenState();
}

class _SubtotalEditorScreenState extends ConsumerState<_SubtotalEditorScreen> {
  late final TextEditingController _nameController;
  late final Set<int> _selected;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initial?.name ?? '');
    _selected = {...?widget.initial?.accountIds};
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(
      BalanceSubtotal(
        name: _nameController.text.trim(),
        accountIds: _selected.toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final entries = flattenAccounts(accounts);
    final canSave =
        _nameController.text.trim().isNotEmpty && _selected.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.initial == null ? 'Nuevo subtotal' : 'Editar subtotal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Guardar',
            onPressed: canSave ? _save : null,
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Nombre del subtotal',
                hintText: 'p. ej. Ahorros, Efectivo…',
                prefixIcon: Icon(Icons.functions),
              ),
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Cuentas a sumar',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          if (accounts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No hay cuentas.'),
            ),
          for (final entry in entries)
            CheckboxListTile(
              contentPadding:
                  EdgeInsets.only(left: 16 + entry.depth * 24.0, right: 16),
              secondary: Icon(iconByName(entry.value.iconName),
                  color: Color(entry.value.colorValue)),
              title: Text(entry.value.name),
              value: _selected.contains(entry.value.id),
              onChanged: (checked) => setState(() {
                if (checked ?? false) {
                  _selected.add(entry.value.id);
                } else {
                  _selected.remove(entry.value.id);
                }
              }),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
