import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../sync/net/sync_protocol.dart';
import 'web_api_client.dart';
import 'web_providers.dart';
import 'web_shell.dart';

/// App raíz de la webapp de escritorio. Muestra la pantalla de conexión hasta
/// que se empareja con el móvil; después, el panel de escritorio.
class WebApp extends ConsumerWidget {
  const WebApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(webClientProvider) != null;
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF2196F3));
    final darkScheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF2196F3), brightness: Brightness.dark);
    return MaterialApp(
      title: 'Finanzas · Escritorio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      darkTheme: ThemeData(colorScheme: darkScheme, useMaterial3: true),
      home: connected ? const WebShell() : const WebConnectScreen(),
    );
  }
}

class WebConnectScreen extends ConsumerStatefulWidget {
  const WebConnectScreen({super.key});
  @override
  ConsumerState<WebConnectScreen> createState() => _WebConnectScreenState();
}

class _WebConnectScreenState extends ConsumerState<WebConnectScreen> {
  late final TextEditingController _host;
  late final TextEditingController _port;
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Si la webapp la sirve el propio móvil, el origen ya es su IP:puerto.
    final base = Uri.base;
    _host = TextEditingController(text: base.host.isEmpty ? '' : base.host);
    _port = TextEditingController(
        text: base.hasPort ? '${base.port}' : '${SyncProtocol.defaultPort}');
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final port = int.tryParse(_port.text.trim()) ?? SyncProtocol.defaultPort;
    final client = WebApiClient(
      baseUri: Uri(scheme: 'http', host: _host.text.trim(), port: port),
    );
    try {
      await client.pair(
        pin: _pin.text.trim(),
        deviceId: const Uuid().v4(),
        displayName: 'Navegador (PC)',
      );
      ref.read(webClientProvider.notifier).state = client;
    } catch (e) {
      setState(() => _error = 'No se pudo conectar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.wifi_tethering,
                      size: 48, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 12),
                  Text('Conectar con tu móvil',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Activa el servidor Wi-Fi en la app del móvil e introduce sus '
                    'datos. Ambos en la misma red.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _host,
                    decoration: const InputDecoration(
                        labelText: 'IP del móvil', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _port,
                          decoration: const InputDecoration(
                              labelText: 'Puerto',
                              border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _pin,
                          decoration: const InputDecoration(
                              labelText: 'PIN', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : _connect,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.link),
                    label: const Text('Conectar'),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
