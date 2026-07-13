import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/isar_provider.dart';
import '../../core/money/money.dart';
import '../../core/platform/wallet_notifications.dart';
import '../../data/models/app_settings.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../wallet/wallet_ingest_service.dart';
import '../wallet/wallet_notification_parser.dart';

/// Ajustes de la lectura de notificaciones de Google Wallet: activar, conceder
/// acceso a notificaciones, cuenta por defecto, apps de origen, procesar ahora y
/// un visor de las notificaciones capturadas (para afinar/depurar). Todo son
/// campos **locales** de este dispositivo (no se sincronizan ni se respaldan).
class WalletSettingsScreen extends ConsumerStatefulWidget {
  const WalletSettingsScreen({super.key});

  @override
  ConsumerState<WalletSettingsScreen> createState() =>
      _WalletSettingsScreenState();
}

class _WalletSettingsScreenState extends ConsumerState<WalletSettingsScreen>
    with WidgetsBindingObserver {
  bool? _granted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver de la pantalla del sistema (conceder acceso), refrescar estado.
    if (state == AppLifecycleState.resumed) _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    final granted = await WalletNotifications.isPermissionGranted();
    if (mounted) setState(() => _granted = granted);
  }

  SettingsRepository get _repo => ref.read(settingsRepositoryProvider);

  Future<void> _update(void Function(AppSettings) mutate) async {
    await _repo.update(mutate);
    final s = await _repo.getOrCreate();
    if (s.walletReaderEnabled) {
      await WalletNotifications.setSourcePackages(s.walletSourcePackages);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(currentSettingsProvider);
    final enabled = settings.walletReaderEnabled;
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final granted = _granted;

    return Scaffold(
      appBar: AppBar(title: const Text('Notificaciones de Wallet')),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Leer notificaciones de Wallet'),
            subtitle: const Text(
                'Al pagar con el móvil, crea el gasto automáticamente con su '
                'importe, comercio y categoría.'),
            value: enabled,
            onChanged: (v) async {
              await _update((s) => s.walletReaderEnabled = v);
              if (v) await _refreshPermission();
            },
          ),
          const Divider(),
          const _Header('Permiso'),
          ListTile(
            enabled: enabled,
            leading: Icon(
              granted == true ? Icons.check_circle : Icons.error_outline,
              color: granted == true
                  ? Colors.green
                  : Theme.of(context).colorScheme.error,
            ),
            title: const Text('Acceso a las notificaciones'),
            subtitle: Text(granted == null
                ? 'Comprobando…'
                : granted
                    ? 'Concedido'
                    : 'No concedido: sin esto no se pueden leer los pagos'),
            trailing: const Icon(Icons.open_in_new),
            onTap: enabled
                ? () async {
                    await WalletNotifications.openListenerSettings();
                  }
                : null,
          ),
          const Divider(),
          const _Header('Cuenta'),
          ListTile(
            enabled: enabled,
            leading: const Icon(Icons.account_balance),
            title: const Text('Cuenta de los gastos'),
            subtitle: Text(_accountLabel(settings.walletDefaultAccountId,
                {for (final a in accounts) a.id: a.name})),
            trailing: const Icon(Icons.edit_outlined),
            onTap: enabled
                ? () => _pickAccount(context, accounts, settings)
                : null,
          ),
          const Divider(),
          const _Header('Apps de origen'),
          for (final pkg in settings.walletSourcePackages)
            ListTile(
              enabled: enabled,
              dense: true,
              leading: const Icon(Icons.apps),
              title: Text(_appLabel(pkg)),
              subtitle: Text(pkg),
              trailing: settings.walletSourcePackages.length > 1
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: enabled
                          ? () => _update((s) => s.walletSourcePackages = [
                                ...s.walletSourcePackages..remove(pkg)
                              ])
                          : null,
                    )
                  : null,
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Añadir app de origen'),
              onPressed: enabled ? () => _addSourcePackage(context) : null,
            ),
          ),
          const Divider(),
          const _Header('Herramientas'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.sync),
                  label: const Text('Procesar ahora'),
                  onPressed: enabled ? () => _processNow(context) : null,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Ver notificaciones capturadas'),
                  onPressed: enabled ? () => _showCaptured(context) : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _processNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final n = await WalletIngestService(ref.read(isarProvider)).drainAndProcess();
    messenger.showSnackBar(SnackBar(
      content: Text(n == 0
          ? 'No había pagos nuevos que procesar'
          : 'Creados $n gasto(s) desde Wallet'),
    ));
  }

  Future<void> _addSourcePackage(BuildContext context) async {
    final controller = TextEditingController();
    final pkg = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Añadir app de origen'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nombre del paquete',
            hintText: 'com.ejemplo.app',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Añadir'),
          ),
        ],
      ),
    );
    if (pkg == null || pkg.isEmpty) return;
    await _update((s) {
      if (!s.walletSourcePackages.contains(pkg)) {
        s.walletSourcePackages = [...s.walletSourcePackages, pkg];
      }
    });
  }

  Future<void> _pickAccount(
    BuildContext context,
    List<dynamic> accounts,
    AppSettings settings,
  ) async {
    final current = settings.walletDefaultAccountId;
    Widget option(int id, String label) => ListTile(
          leading: Icon(id == current
              ? Icons.radio_button_checked
              : Icons.radio_button_unchecked),
          title: Text(label),
          onTap: () {
            _update((s) => s.walletDefaultAccountId = id);
            Navigator.pop(context);
          },
        );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            option(0, 'Primera cuenta activa'),
            for (final a in accounts) option(a.id as int, a.name as String),
          ],
        ),
      ),
    );
  }

  Future<void> _showCaptured(BuildContext context) async {
    final captured = await WalletNotifications.peekBuffer();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, controller) {
          if (captured.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Sin notificaciones capturadas todavía.\n'
                    'Paga con Google Wallet y vuelve a mirar aquí.',
                    textAlign: TextAlign.center),
              ),
            );
          }
          final df = DateFormat('d MMM, HH:mm', 'es_ES');
          return ListView.separated(
            controller: controller,
            itemCount: captured.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final c = captured[captured.length - 1 - i]; // más recientes arriba
              final parsed = parseWalletNotification(
                package: c.package,
                title: c.title,
                text: c.text,
                postedAt: c.postedAt,
              );
              return ListTile(
                title: Text(c.title.isEmpty ? '(sin título)' : c.title),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.text),
                    const SizedBox(height: 2),
                    Text(
                      parsed == null
                          ? '❔ No parece un pago'
                          : '✅ ${Money(parsed.cents).format()} · '
                              '${parsed.merchant.isEmpty ? "(sin comercio)" : parsed.merchant}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                trailing: Text(df.format(c.postedAt),
                    style: Theme.of(context).textTheme.bodySmall),
                isThreeLine: true,
              );
            },
          );
        },
      ),
    );
  }

  static String _accountLabel(int id, Map<int, String> names) {
    if (id == 0) return 'Primera cuenta activa';
    return names[id] ?? 'Primera cuenta activa';
  }

  static String _appLabel(String pkg) {
    if (pkg == 'com.google.android.apps.walletnfcrel') return 'Google Wallet';
    return pkg.split('.').last;
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
