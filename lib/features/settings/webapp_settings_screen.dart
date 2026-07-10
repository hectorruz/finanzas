import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/repositories/settings_repository.dart';
import '../sync/net/sync_protocol.dart';
import '../sync/sync_service.dart';
import '../web/web_dashboard_cards.dart';

/// Ajustes **propios de la webapp de escritorio** (Ajustes → "Webapp de
/// escritorio"). A diferencia del apartado de sincronización, aquí solo hay lo
/// que atañe a usar Finanzas desde el navegador: encender el servidor que la
/// sirve, su dirección (con copiar y QR para abrirla desde el PC) y qué tarjetas
/// muestra el panel de la web.
class WebappSettingsScreen extends ConsumerWidget {
  const WebappSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final server = ref.watch(syncServerControllerProvider);
    final controller = ref.read(syncServerControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Webapp de escritorio')),
      body: !settings.syncIsAdmin
          ? const _NotAdminBody()
          : ListView(
              children: [
                const _Header('Servidor'),
                SwitchListTile(
                  secondary: const Icon(Icons.dns_outlined),
                  title: const Text('Servir la webapp'),
                  subtitle: Text(server.running
                      ? 'Activa: ábrela en el navegador de tu ordenador.'
                      : 'Enciende el servidor para usar la webapp.'),
                  value: server.running,
                  onChanged: (v) =>
                      v ? controller.start() : controller.stop(),
                ),
                if (server.error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text('Error: ${server.error}',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                if (server.running) ..._addressWidgets(context, server),
                const Divider(),
                const _Header('Tarjetas del panel web'),
                _CardsEditor(cards: settings.webDashboardCards),
              ],
            ),
    );
  }

  List<Widget> _addressWidgets(BuildContext context, SyncServerState server) {
    final port = server.port ?? SyncProtocol.defaultPort;
    if (server.ips.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('No se detectó ninguna IP de red local.'),
        ),
      ];
    }
    return [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Text(
            'Ábrela en el navegador de un ordenador en la misma Wi-Fi, o '
            'escanea el QR con la cámara del móvil:'),
      ),
      for (final ip in server.ips) _AddressTile(url: 'http://$ip:$port'),
    ];
  }
}

class _AddressTile extends StatelessWidget {
  const _AddressTile({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.desktop_windows_outlined),
          title: Text(url),
          trailing: IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copiar enlace',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enlace copiado.')),
                );
              }
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: QrImageView(
              data: url,
              size: 168,
              backgroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

/// Editor de las tarjetas del panel de la webapp (`AppSettings.webDashboardCards`).
/// Reutiliza el catálogo compartido `kWebDashboardCatalog`. Solo afecta al panel
/// de la web, no al inicio del móvil.
class _CardsEditor extends ConsumerWidget {
  const _CardsEditor({required this.cards});
  final List<String> cards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(settingsRepositoryProvider);
    // Claves visibles válidas, en orden (vacío = layout por defecto).
    final visible = cards.isEmpty
        ? List<String>.from(kDefaultWebDashboard)
        : cards.where((k) => webCardByKey(k) != null).toList();
    final hidden = kWebDashboardCatalog
        .map((c) => c.key)
        .where((k) => !visible.contains(k))
        .toList();

    Future<void> save(List<String> list) =>
        repo.update((s) => s.webDashboardCards = list);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Elige qué tarjetas se ven y en qué orden. Solo afecta al panel de '
            'la webapp (no al inicio del móvil). Mantén pulsado para reordenar.',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          onReorder: (oldIndex, newIndex) {
            final list = [...visible];
            if (newIndex > oldIndex) newIndex--;
            final item = list.removeAt(oldIndex);
            list.insert(newIndex, item);
            save(list);
          },
          children: [
            for (final key in visible)
              ListTile(
                key: ValueKey(key),
                leading: Icon(webCardByKey(key)?.icon ?? Icons.dashboard),
                title: Text(webCardLabel(key)),
                trailing: IconButton(
                  icon: const Icon(Icons.visibility_off_outlined),
                  tooltip: 'Ocultar',
                  onPressed: () =>
                      save(visible.where((k) => k != key).toList()),
                ),
              ),
          ],
        ),
        if (hidden.isNotEmpty) ...[
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text('Ocultas'),
          ),
          for (final key in hidden)
            ListTile(
              leading: Icon(webCardByKey(key)?.icon ?? Icons.dashboard),
              title: Text(webCardLabel(key)),
              trailing: IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Mostrar',
                onPressed: () => save([...visible, key]),
              ),
            ),
        ],
      ],
    );
  }
}

class _NotAdminBody extends StatelessWidget {
  const _NotAdminBody();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.desktop_windows_outlined, size: 40),
          SizedBox(height: 12),
          Text('Solo desde el dispositivo principal',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text(
              'La webapp se sirve desde el dispositivo principal de la '
              'sincronización. Configúrala allí.'),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
