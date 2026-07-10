import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../web_dashboard_cards.dart';
import '../web_providers.dart';
import '../web_session.dart';
import '../widgets/web_pickers.dart';
import '../widgets/web_ui.dart';

/// Ajustes de la webapp: tema, privacidad, tarjetas del panel e info del
/// servidor. El tema/privacidad/tarjetas se guardan en los ajustes del móvil
/// (mismo `AppSettings`), así que también afectan a la app.
class WebSettingsPage extends ConsumerWidget {
  const WebSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(webSettingsProvider);

    return WebPage(
      title: 'Ajustes',
      maxWidth: 720,
      child: settingsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(48),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Text('Error: $e'),
        data: (settings) {
          final client = ref.read(webClientProvider);
          Future<void> patch(Map<String, dynamic> body) async {
            await client?.putSettings(body);
            bumpWebRefresh(ref);
          }

          // Tarjetas del panel de la web (independiente del inicio del móvil).
          final visibleCards = settings.webDashboardCards.isEmpty
              ? kDefaultWebDashboard
              : settings.webDashboardCards
                  .where((k) => webCardByKey(k) != null)
                  .toList();
          final hiddenCards = kWebDashboardCatalog
              .map((c) => c.key)
              .where((k) => !visibleCards.contains(k))
              .toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WebCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Apariencia',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Expanded(child: Text('Tema')),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                                value: 'system', label: Text('Sistema')),
                            ButtonSegment(value: 'light', label: Text('Claro')),
                            ButtonSegment(value: 'dark', label: Text('Oscuro')),
                          ],
                          selected: {settings.themeMode},
                          onSelectionChanged: (s) async {
                            ref
                                .read(webThemeModeOverrideProvider.notifier)
                                .state = null;
                            await patch({'themeMode': s.first});
                          },
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Negro puro (AMOLED) en oscuro'),
                      value: settings.amoled,
                      onChanged: (v) => patch({'amoled': v}),
                    ),
                    const SizedBox(height: 8),
                    Text('Color de acento',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      'Se aplica al tema de la webapp (y a la app cuando el color '
                      'del sistema/Material You está desactivado).',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.outline),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final c in kWebColorPalette)
                          _AccentSwatch(
                            colorValue: c,
                            selected: settings.seedColorValue == c,
                            onTap: () => patch({'seedColorValue': c}),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              WebCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Privacidad',
                        style: Theme.of(context).textTheme.titleMedium),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Ocultar importes por defecto'),
                      subtitle: const Text(
                          'También puedes alternarlo con el ojo de la barra superior.'),
                      value: settings.hideAmounts,
                      onChanged: (v) async {
                        ref.read(webHideAmountsProvider.notifier).state = v;
                        await patch({'hideAmounts': v});
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              WebCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tarjetas del panel',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Elige qué tarjetas se ven y en qué orden. Solo afecta al '
                      'panel de la webapp (no al inicio del móvil). Arrastra para '
                      'reordenar.',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.outline),
                    ),
                    const SizedBox(height: 8),
                    ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: true,
                      onReorder: (oldIndex, newIndex) {
                        final list = [...visibleCards];
                        if (newIndex > oldIndex) newIndex--;
                        final item = list.removeAt(oldIndex);
                        list.insert(newIndex, item);
                        patch({'webDashboardCards': list});
                      },
                      children: [
                        for (final key in visibleCards)
                          ListTile(
                            key: ValueKey(key),
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.drag_handle),
                            title: Text(webCardLabel(key)),
                            trailing: IconButton(
                              icon: const Icon(Icons.visibility_off),
                              tooltip: 'Ocultar',
                              onPressed: () => patch({
                                'webDashboardCards': visibleCards
                                    .where((k) => k != key)
                                    .toList(),
                              }),
                            ),
                          ),
                      ],
                    ),
                    if (hiddenCards.isNotEmpty) ...[
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 4),
                        child: Text('Ocultas',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.outline)),
                      ),
                      for (final key in hiddenCards)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(webCardLabel(key)),
                          trailing: IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            tooltip: 'Mostrar',
                            onPressed: () => patch({
                              'webDashboardCards': [...visibleCards, key],
                            }),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              WebCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Servidor',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.wifi_tethering),
                      title: const Text('Conectado a'),
                      subtitle: Text(
                          '${WebSession.host ?? '—'}:${WebSession.port ?? '—'}'),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.logout),
                        label: const Text('Desconectar'),
                        onPressed: () {
                          WebSession.clear();
                          ref.read(webClientProvider)?.close();
                          ref.read(webClientProvider.notifier).state = null;
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Muestra un color de la paleta como círculo seleccionable (check si activo).
class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.colorValue,
    required this.selected,
    required this.onTap,
  });

  final int colorValue;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(colorValue);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.onSurface, width: 3)
              : null,
        ),
        child: selected
            ? Icon(Icons.check,
                color: ThemeData.estimateBrightnessForColor(color) ==
                        Brightness.dark
                    ? Colors.white
                    : Colors.black,
                size: 20)
            : null,
      ),
    );
  }
}
