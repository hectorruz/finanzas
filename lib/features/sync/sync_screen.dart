import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/router/app_router.dart';
import '../../data/repositories/settings_repository.dart';
import 'net/lan_sync_server.dart';
import 'net/sync_protocol.dart';
import 'sync_review_screen.dart';
import 'sync_service.dart';

/// Pantalla de sincronización LAN. Un lado levanta el servidor (admin) y el otro
/// se conecta (vinculado). El tráfico es HTTP plano en la red local, protegido
/// por PIN al emparejar y por token en cada petición.
class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(currentSettingsProvider).syncIsAdmin;
    return Scaffold(
      appBar: AppBar(title: const Text('Sincronización Wi-Fi')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _HttpWarning(),
          const SizedBox(height: 8),
          if (isAdmin) const _ServerPanel() else const _ClientPanel(),
        ],
      ),
    );
  }
}

class _HttpWarning extends StatelessWidget {
  const _HttpWarning();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.wifi_lock),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Usa solo en tu red doméstica de confianza. Los datos viajan sin '
                'cifrar por la red local; cada petición exige el token de '
                'emparejamiento.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===================== ADMIN =====================

class _ServerPanel extends ConsumerWidget {
  const _ServerPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(syncServerControllerProvider);
    final controller = ref.read(syncServerControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Este dispositivo es el principal',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Levanta el servidor y deja que el otro dispositivo se conecte a la '
          'misma red Wi-Fi.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (!state.running)
          FilledButton.icon(
            onPressed: controller.start,
            icon: const Icon(Icons.wifi_tethering),
            label: const Text('Activar servidor'),
          )
        else ...[
          _PairingInfo(state: state),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: controller.stop,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Detener servidor'),
          ),
          const SizedBox(height: 16),
          Text('Cambios por revisar',
              style: Theme.of(context).textTheme.titleSmall),
          if (state.pending.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Aún no ha llegado nada del otro dispositivo.'),
            )
          else
            for (final s in state.pending)
              _PendingSessionTile(session: s, controller: controller),
        ],
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Error: ${state.error}',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ],
    );
  }
}

class _PairingInfo extends StatelessWidget {
  const _PairingInfo({required this.state});
  final SyncServerState state;

  @override
  Widget build(BuildContext context) {
    final ip = state.ips.isNotEmpty ? state.ips.first : '—';
    final port = state.port ?? SyncProtocol.defaultPort;
    final payload = 'finanzas-sync:host=$ip;port=$port;pin=${state.pin}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Center(
              child: QrImageView(
                data: payload,
                size: 180,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            _kv(context, 'IP', state.ips.isEmpty ? '—' : state.ips.join(', ')),
            _kv(context, 'Puerto', '$port'),
            _kv(context, 'PIN', state.pin, big: true),
            const SizedBox(height: 4),
            Text(
              'Introduce estos datos (o escanea el QR) en el otro dispositivo.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v, {bool big = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: Theme.of(context).textTheme.labelMedium),
          Text(v,
              style: big
                  ? Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 4)
                  : Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _PendingSessionTile extends StatelessWidget {
  const _PendingSessionTile({required this.session, required this.controller});
  final ReviewSession session;
  final SyncServerController controller;

  @override
  Widget build(BuildContext context) {
    final p = session.plan;
    return Card(
      child: ListTile(
        title: Text(session.peerName),
        subtitle: Text('${p.additions.length} nuevos · '
            '${p.cleanUpdates.length} actualizaciones · '
            '${p.conflicts.length} conflictos'),
        trailing: FilledButton(
          onPressed: () => context.push(
            Routes.syncReview,
            extra: SyncReviewArgs(
              plan: p,
              peerName: session.peerName,
              onConfirm: (decisions) =>
                  controller.finalizeSession(session, decisions),
            ),
          ),
          child: const Text('Revisar'),
        ),
      ),
    );
  }
}

// ===================== VINCULADO =====================

class _ClientPanel extends ConsumerStatefulWidget {
  const _ClientPanel();
  @override
  ConsumerState<_ClientPanel> createState() => _ClientPanelState();
}

class _ClientPanelState extends ConsumerState<_ClientPanel> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '${SyncProtocol.defaultPort}');
  final _pin = TextEditingController();
  bool _busy = false;
  bool _paired = false;
  String? _status;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _pin.dispose();
    super.dispose();
  }

  int get _portNum => int.tryParse(_port.text.trim()) ?? SyncProtocol.defaultPort;

  Future<void> _pair() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final name = await ref.read(linkedSyncServiceProvider).pair(
            host: _host.text.trim(),
            port: _portNum,
            pin: _pin.text.trim(),
          );
      setState(() {
        _paired = true;
        _status = 'Emparejado con $name.';
      });
    } catch (e) {
      setState(() => _status = 'No se pudo emparejar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sync() async {
    setState(() {
      _busy = true;
      _status = 'Enviando cambios y esperando al principal…';
    });
    try {
      final outcome = await ref.read(linkedSyncServiceProvider).sync(
            host: _host.text.trim(),
            port: _portNum,
          );
      setState(() => _status = outcome.rejected
          ? 'El principal rechazó la sincronización.'
          : 'Sincronizado. ${outcome.applied} registros al día.');
    } catch (e) {
      setState(() => _status = 'Error al sincronizar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Conectar con el dispositivo principal',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Ambos en la misma Wi-Fi. Escribe la IP, el puerto y el PIN que muestra '
          'el principal.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _host,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'IP del principal',
            hintText: '192.168.1.42',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _port,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Puerto',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _pin,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'PIN',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _pair,
          icon: const Icon(Icons.link),
          label: const Text('Emparejar'),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: (_busy || !_paired) ? null : _sync,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sync),
          label: const Text('Sincronizar ahora'),
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_status!),
          ),
      ],
    );
  }
}
