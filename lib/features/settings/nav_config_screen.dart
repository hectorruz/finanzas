import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/enums.dart';
import '../../data/repositories/settings_repository.dart';

/// Permite elegir y reordenar qué secciones aparecen en la barra inferior.
/// Ajustes siempre está visible (no se puede ocultar) y queda la última.
class NavConfigScreen extends ConsumerWidget {
  const NavConfigScreen({super.key});

  static const _labels = {
    NavSection.dashboard: 'Inicio',
    NavSection.movements: 'Movimientos',
    NavSection.receipts: 'Tickets',
    NavSection.goals: 'Objetivos',
    NavSection.settings: 'Ajustes',
  };

  static const _icons = {
    NavSection.dashboard: Icons.home_outlined,
    NavSection.movements: Icons.swap_vert_outlined,
    NavSection.receipts: Icons.receipt_long_outlined,
    NavSection.goals: Icons.flag_outlined,
    NavSection.settings: Icons.settings_outlined,
  };

  // Secciones configurables (Ajustes es fija).
  static final _configurable = NavSection.values
      .where((s) => s != NavSection.settings)
      .toList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final repo = ref.read(settingsRepositoryProvider);

    final active =
        settings.sections.where((s) => s != NavSection.settings).toList();
    final inactive =
        _configurable.where((s) => !active.contains(s)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Personalizar barra inferior')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Secciones activas (mantén pulsado para reordenar)',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorder: (oldIndex, newIndex) {
              final list = [...active];
              if (newIndex > oldIndex) newIndex--;
              final item = list.removeAt(oldIndex);
              list.insert(newIndex, item);
              repo.update(
                  (s) => s.navSections = list.map((e) => e.name).toList());
            },
            children: [
              for (final section in active)
                ListTile(
                  key: ValueKey(section.name),
                  leading: Icon(_icons[section]),
                  title: Text(_labels[section] ?? section.name),
                  trailing: IconButton(
                    icon: const Icon(Icons.visibility_off),
                    // No permitir quedarse sin secciones (además de Ajustes).
                    onPressed: active.length <= 1
                        ? null
                        : () => repo.update((s) => s.navSections = active
                            .where((e) => e != section)
                            .map((e) => e.name)
                            .toList()),
                  ),
                ),
            ],
          ),
          if (inactive.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Secciones ocultas',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final section in inactive)
              ListTile(
                leading: Icon(_icons[section]),
                title: Text(_labels[section] ?? section.name),
                trailing: IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => repo.update((s) => s.navSections =
                      [...active.map((e) => e.name), section.name]),
                ),
              ),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Ajustes'),
            subtitle: const Text('Siempre visible'),
            enabled: false,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
