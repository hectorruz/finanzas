import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
