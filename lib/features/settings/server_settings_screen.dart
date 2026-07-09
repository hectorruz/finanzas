import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/app_settings.dart';
import '../../data/repositories/settings_repository.dart';
import '../sync/net/sync_protocol.dart';
import '../sync/sync_service.dart';

/// Ajustes del servidor de sincronización (principal): lo básico (nombre del
/// dispositivo, ejecutar en segundo plano, auto-inicio) y lo avanzado (puerto,
/// PIN, revocar dispositivos), más el registro de actividad de los vinculados.
class ServerSettingsScreen extends ConsumerWidget {
  const ServerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final repo = ref.read(settingsRepositoryProvider);
    final server = ref.watch(syncServerControllerProvider);
    final controller = ref.read(syncServerControllerProvider.notifier);

    // Guarda un cambio y, si toca puerto/PIN con el servidor activo, lo reinicia
    // para que el cambio surta efecto de inmediato.
    Future<void> updateRestarting(void Function(AppSettings) mutate) async {
      await repo.update(mutate);
      if (server.running) {
        await controller.restart();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Servidor reiniciado para aplicar los cambios.')));
        }
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes del servidor')),
      body: ListView(
        children: [
          const _Header('Básico'),
          ListTile(
            leading: const Icon(Icons.smartphone),
            title: const Text('Nombre del dispositivo'),
            subtitle: Text(settings.syncDeviceName.isEmpty
                ? 'Sin nombre'
                : settings.syncDeviceName),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final name = await _editText(
                context,
                title: 'Nombre del dispositivo',
                initial: settings.syncDeviceName,
                hint: 'p. ej. Móvil de Héctor',
              );
              if (name != null) {
                await repo.update((s) => s.syncDeviceName = name.trim());
              }
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.desktop_access_disabled),
            title: const Text('Ejecutar en segundo plano'),
            subtitle: const Text(
                'Mantiene el servidor activo con la pantalla apagada mediante '
                'una notificación permanente.'),
            value: settings.syncKeepAliveInBackground,
            onChanged: (v) async {
              await repo.update((s) => s.syncKeepAliveInBackground = v);
              await controller.applyKeepAlive(v);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.play_circle_outline),
            title: const Text('Iniciar el servidor automáticamente'),
            subtitle: const Text(
                'Levanta el servidor al abrir la app (si es el principal).'),
            value: settings.syncAutoStartServer,
            onChanged: (v) => repo.update((s) => s.syncAutoStartServer = v),
          ),
          const Divider(),
          const _Header('Sincronización automática'),
          SwitchListTile(
            secondary: const Icon(Icons.sync),
            title: const Text('Sincronizar automáticamente'),
            subtitle: const Text(
                'El dispositivo vinculado se pone al día solo al abrir la app y '
                'al conectarse a la Wi-Fi.'),
            value: settings.syncLinkedAutoSyncEnabled,
            onChanged: (v) =>
                repo.update((s) => s.syncLinkedAutoSyncEnabled = v),
          ),
          const Divider(),
          Theme(
            data: Theme.of(context)
                .copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: const Icon(Icons.tune),
              title: const Text('Avanzado'),
              childrenPadding: EdgeInsets.zero,
              children: [
                ListTile(
                  leading: const Icon(Icons.settings_ethernet),
                  title: const Text('Puerto'),
                  subtitle: Text(
                      '${settings.syncPort > 0 ? settings.syncPort : SyncProtocol.defaultPort}'),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () async {
                    final port = await _editPort(context, settings.syncPort);
                    if (port != null) {
                      await updateRestarting((s) => s.syncPort = port);
                    }
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.password),
                  title: const Text('Requerir PIN'),
                  subtitle: Text(settings.syncRequirePin
                      ? 'El otro dispositivo debe teclear el PIN para emparejar.'
                      : '⚠ Cualquiera en esta Wi-Fi puede emparejar sin código.'),
                  value: settings.syncRequirePin,
                  onChanged: (v) async {
                    if (!v && !await _confirmDisablePin(context)) return;
                    await updateRestarting((s) => s.syncRequirePin = v);
                  },
                ),
                if (settings.syncRequirePin)
                  ListTile(
                    leading: const Icon(Icons.pin),
                    title: const Text('PIN de emparejamiento'),
                    subtitle: Text(settings.syncFixedPin.isEmpty
                        ? 'Aleatorio en cada arranque'
                        : 'Fijo: ${settings.syncFixedPin}'),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () async {
                      final pin = await _editPin(context, settings.syncFixedPin);
                      if (pin != null) {
                        await updateRestarting((s) => s.syncFixedPin = pin);
                      }
                    },
                  ),
                if (server.running &&
                    server.requirePin &&
                    settings.syncFixedPin.isEmpty)
                  ListTile(
                    leading: const Icon(Icons.autorenew),
                    title: const Text('Regenerar PIN ahora'),
                    subtitle: const Text('Genera un PIN nuevo al instante.'),
                    onTap: () async {
                      await controller.restart();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('PIN regenerado.')),
                        );
                      }
                    },
                  ),
                ListTile(
                  leading: Icon(Icons.link_off,
                      color: Theme.of(context).colorScheme.error),
                  title: Text('Revocar todos los dispositivos',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                  subtitle: const Text(
                      'Los vinculados tendrán que volver a emparejarse.'),
                  onTap: () async {
                    final ok = await _confirmRevokeAll(context);
                    if (ok) {
                      await controller.revokeAllLinkedPeers();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Dispositivos revocados.')),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
          const Divider(),
          const _Header('Actividad'),
          const _ActivityLog(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<String?> _editText(
    BuildContext context, {
    required String title,
    required String initial,
    String? hint,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  /// Devuelve el puerto nuevo (1024–65535) o null si se cancela / es inválido.
  Future<int?> _editPort(BuildContext context, int current) async {
    final controller = TextEditingController(
        text: '${current > 0 ? current : SyncProtocol.defaultPort}');
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Puerto'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            helperText: 'Entre 1024 y 65535 (por defecto 8422)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text)),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (value == null) return null;
    if (value < 1024 || value > 65535) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Puerto no válido (1024–65535).')),
        );
      }
      return null;
    }
    return value;
  }

  /// PIN fijo de 6 dígitos, o cadena vacía para "aleatorio". Null si se cancela.
  Future<String?> _editPin(BuildContext context, String current) async {
    final controller = TextEditingController(text: current);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PIN de emparejamiento'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            helperText: 'Déjalo vacío para uno aleatorio en cada arranque',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (value == null) return null;
    if (value.isNotEmpty && value.length != 6) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El PIN debe tener 6 dígitos.')),
        );
      }
      return null;
    }
    return value;
  }

  Future<bool> _confirmDisablePin(BuildContext context) async =>
      await _confirm(
        context,
        title: 'Emparejar sin PIN',
        message:
            'Cualquier dispositivo en esta misma Wi-Fi podrá emparejarse sin '
            'código. Úsalo solo en una red de confianza. ¿Continuar?',
        confirmLabel: 'Desactivar PIN',
      );

  Future<bool> _confirmRevokeAll(BuildContext context) async => await _confirm(
        context,
        title: 'Revocar todos los dispositivos',
        message:
            'Se invalidará el acceso de todos los dispositivos vinculados. '
            'Tendrán que volver a emparejarse con el PIN. ¿Continuar?',
        confirmLabel: 'Revocar',
      );

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

/// Registro de actividad: los dispositivos vinculados y su última sincronización.
class _ActivityLog extends ConsumerWidget {
  const _ActivityLog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peers = ref.watch(linkedPeersProvider).valueOrNull ?? const [];
    if (peers.isEmpty) {
      return const ListTile(
        leading: Icon(Icons.history),
        title: Text('Sin dispositivos vinculados'),
        subtitle: Text('Aquí verás cuándo sincronizó cada uno por última vez.'),
      );
    }
    return Column(
      children: [
        for (final peer in peers)
          ListTile(
            leading: const Icon(Icons.smartphone),
            title: Text(peer.displayName),
            subtitle: Text(peer.lastSyncAt == null
                ? 'Aún no ha sincronizado'
                : 'Última sincronización: '
                    '${DateFormat('d MMM yyyy, HH:mm', 'es_ES').format(peer.lastSyncAt!)}'),
          ),
      ],
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
