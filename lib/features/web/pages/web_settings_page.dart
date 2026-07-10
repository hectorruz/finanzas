import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../web_providers.dart';
import '../web_session.dart';
import '../widgets/web_ui.dart';

/// Ajustes de la webapp: tema, privacidad, tarjetas del panel e info del
/// servidor. El tema/privacidad/tarjetas se guardan en los ajustes del móvil
/// (mismo `AppSettings`), así que también afectan a la app.
class WebSettingsPage extends ConsumerWidget {
  const WebSettingsPage({super.key});

  static const _dashboardCards = <String, String>{
    'totalBalance': 'Balance total',
    'accountsBalance': 'Cuentas',
    'monthComparison': 'Comparativa del mes y gráficas',
    'recentMovements': 'Últimos movimientos',
    'goals': 'Objetivos',
  };

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

          final cards = settings.dashboardCards;
          bool cardOn(String c) => cards.isEmpty || cards.contains(c);

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
                      'Elige qué se muestra en el panel (afecta también a la app).',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.outline),
                    ),
                    const SizedBox(height: 8),
                    for (final e in _dashboardCards.entries)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(e.value),
                        value: cardOn(e.key),
                        onChanged: (v) {
                          final next = <String>[
                            for (final c in _dashboardCards.keys)
                              if (c == e.key ? (v ?? false) : cardOn(c)) c,
                          ];
                          patch({'dashboardCards': next});
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
