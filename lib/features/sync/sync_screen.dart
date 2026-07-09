import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/router/app_router.dart';
import '../../data/backup_service.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/sync_peer.dart';
import '../../data/repositories/settings_repository.dart';
import 'net/lan_sync_server.dart';
import 'net/sync_protocol.dart';
import 'net/sync_qr.dart';
import 'qr_scan_screen.dart';
import 'sync_reminder_planner.dart';
import 'sync_reminder_service.dart';
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
        const SizedBox(height: 16),
        const _ReminderSection(),
        const _LinkedDevicesSection(),
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
    final pinText = state.requirePin ? state.pin : 'No requerido';

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
            _kv(context, 'PIN', pinText, big: state.requirePin),
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

class _LinkedDevicesSection extends ConsumerWidget {
  const _LinkedDevicesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peers = ref.watch(linkedPeersProvider).valueOrNull ?? const [];
    if (peers.isEmpty) return const SizedBox.shrink();
    final controller = ref.read(syncServerControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text('Dispositivos vinculados',
            style: Theme.of(context).textTheme.titleSmall),
        for (final peer in peers)
          Card(
            child: ListTile(
              leading: const Icon(Icons.smartphone),
              title: Text(peer.displayName),
              subtitle: Text(peer.lastSyncAt == null
                  ? 'Aún no ha sincronizado'
                  : 'Último sync: '
                      '${DateFormat('d MMM, HH:mm', 'es_ES').format(peer.lastSyncAt!)}'),
              trailing: IconButton(
                icon: const Icon(Icons.link_off),
                tooltip: 'Olvidar (revoca su acceso)',
                onPressed: () => controller.forgetLinkedPeer(peer.id),
              ),
            ),
          ),
      ],
    );
  }
}

class _ReminderSection extends ConsumerWidget {
  const _ReminderSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final repo = ref.read(settingsRepositoryProvider);
    final reminderService = ref.read(syncReminderServiceProvider);

    Future<void> update(void Function(AppSettings) mutate) async {
      await repo.update(mutate);
      await reminderService.reschedule();
    }

    final days = resolveReminderWeekdays(settings.syncReminderWeekdays);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Recordatorio de sincronización'),
              subtitle: const Text(
                  'Un aviso a una hora fija para acordarte de revisar los '
                  'cambios de los dispositivos vinculados.'),
              value: settings.syncReminderEnabled,
              onChanged: (v) => update((s) => s.syncReminderEnabled = v),
            ),
            if (settings.syncReminderEnabled) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hora'),
                trailing: Text(
                  '${settings.syncReminderHour.toString().padLeft(2, '0')}:'
                  '${settings.syncReminderMinute.toString().padLeft(2, '0')}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(
                        hour: settings.syncReminderHour,
                        minute: settings.syncReminderMinute),
                  );
                  if (picked != null) {
                    await update((s) {
                      s.syncReminderHour = picked.hour;
                      s.syncReminderMinute = picked.minute;
                    });
                  }
                },
              ),
              const SizedBox(height: 4),
              Text('Días', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                children: [
                  for (final day in allWeekdays)
                    FilterChip(
                      label: Text(_weekdayLabel(day)),
                      selected: days.contains(day),
                      onSelected: (selected) {
                        final next = {...days};
                        if (selected) {
                          next.add(day);
                        } else if (next.length > 1) {
                          next.remove(day);
                        }
                        update((s) =>
                            s.syncReminderWeekdays = next.toList()..sort());
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _weekdayLabel(int day) =>
      const ['L', 'M', 'X', 'J', 'V', 'S', 'D'][day - 1];
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
  bool _showForm = false;
  bool _autoSelected = false;
  bool _wipeOnPair = false;
  String? _status;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _pin.dispose();
    super.dispose();
  }

  int get _portNum =>
      int.tryParse(_port.text.trim()) ?? SyncProtocol.defaultPort;

  void _selectSaved(SyncPeer peer) {
    final parts = peer.lastAddress.split(':');
    setState(() {
      _host.text = parts.isNotEmpty ? parts[0] : '';
      _port.text = parts.length > 1 ? parts[1] : '${SyncProtocol.defaultPort}';
      _paired = true;
      _showForm = false;
      _status = null;
    });
  }

  Future<void> _forget(SyncPeer peer) async {
    final wasSelected = _host.text == peer.lastAddress.split(':').first;
    await ref.read(linkedSyncServiceProvider).forgetAdmin(peer.id);
    if (wasSelected && mounted) {
      setState(() {
        _paired = false;
        _host.clear();
        _pin.clear();
      });
    }
  }

  Future<void> _pair() async {
    // Opción "borrar datos de este dispositivo": se confirma ANTES de tocar
    // nada. Deja el móvil limpio para adoptar los datos del principal sin
    // duplicar los defaults que sembró al instalarse.
    if (_wipeOnPair && !await _confirmWipe()) return;

    setState(() {
      _busy = true;
      _status = null;
    });
    final host = _host.text.trim();
    final port = _portNum;
    try {
      if (_wipeOnPair) {
        await ref.read(backupServiceProvider).wipeSyncableData();
      }
      final name = await ref.read(linkedSyncServiceProvider).pair(
            host: host,
            port: port,
            pin: _pin.text.trim(),
          );
      setState(() {
        _paired = true;
        _showForm = false;
        _status = _wipeOnPair
            ? 'Emparejado con $name. Sincronizando…'
            : 'Emparejado con $name.';
      });
      // Tras borrar, sincroniza de inmediato para adoptar los datos del
      // principal y que ambos queden idénticos.
      if (_wipeOnPair) {
        final outcome =
            await ref.read(linkedSyncServiceProvider).sync(host: host, port: port);
        if (mounted) {
          setState(() {
            _wipeOnPair = false;
            _status = outcome.rejected
                ? 'Emparejado, pero el principal rechazó la sincronización.'
                : 'Datos adoptados del principal ($name).';
          });
        }
      }
    } catch (e) {
      setState(() => _status = 'No se pudo emparejar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmWipe() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar datos de este dispositivo'),
        content: const Text(
          'Se borrarán las cuentas, categorías, movimientos, tickets y '
          'objetivos de ESTE dispositivo, y adoptará los del principal al '
          'sincronizar. Sirve para que ambos queden iguales, sin duplicados. '
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Borrar y emparejar'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _scanQr() async {
    final result = await Navigator.of(context).push<SyncQrPayload>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (result == null || !mounted) return;
    _host.text = result.host;
    _port.text = '${result.port}';
    _pin.text = result.pin;
    await _pair();
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
    final saved = ref.watch(savedAdminPeersProvider).valueOrNull ?? const [];

    if (!_autoSelected && !_paired && saved.isNotEmpty) {
      _autoSelected = true;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _selectSaved(saved.first));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Conectar con el dispositivo principal',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Ambos en la misma Wi-Fi.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (saved.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Dispositivos guardados',
              style: Theme.of(context).textTheme.titleSmall),
          for (final peer in saved)
            Card(
              child: ListTile(
                leading: const Icon(Icons.smartphone),
                title: Text(peer.displayName),
                subtitle: Text(peer.lastAddress),
                onTap: _busy ? null : () => _selectSaved(peer),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Olvidar',
                  onPressed: _busy ? null : () => _forget(peer),
                ),
              ),
            ),
        ],
        const SizedBox(height: 12),
        if (_paired)
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _sync,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            label: const Text('Sincronizar ahora'),
          ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => setState(() => _showForm = !_showForm),
          icon: Icon(_showForm ? Icons.expand_less : Icons.add_link),
          label: Text(saved.isEmpty
              ? 'Conectar con el principal'
              : 'Añadir otro dispositivo'),
        ),
        if (_showForm || saved.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Escribe la IP, el puerto y el PIN que muestra el principal, o '
            'escanea su código QR.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _host,
                  decoration: const InputDecoration(
                    labelText: 'IP del principal',
                    hintText: '192.168.1.42',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: _busy ? null : _scanQr,
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: 'Escanear código QR',
              ),
            ],
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
          const SizedBox(height: 4),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _wipeOnPair,
            onChanged: _busy
                ? null
                : (v) => setState(() => _wipeOnPair = v ?? false),
            title: const Text('Borrar datos de este dispositivo'),
            subtitle: const Text(
                'Empieza en limpio y adopta los datos del principal (evita '
                'categorías duplicadas al vincular un móvil recién instalado).'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _pair,
            icon: Icon(_wipeOnPair ? Icons.delete_sweep : Icons.link),
            label: Text(_wipeOnPair ? 'Borrar y emparejar' : 'Emparejar'),
          ),
        ],
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_status!),
          ),
      ],
    );
  }
}
