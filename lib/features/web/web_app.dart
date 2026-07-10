import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/enums.dart';
import '../sync/net/sync_protocol.dart';
import 'web_api_client.dart';
import 'web_models.dart';
import 'web_providers.dart';
import 'web_router.dart';
import 'web_session.dart';

/// Router de la webapp, cacheado para no recrearlo en cada rebuild.
final webRouterProvider = Provider<GoRouter>((ref) => buildWebRouter());

/// App raíz de la webapp de escritorio. Reintenta reconectar desde la sesión
/// guardada; si no hay o falla, muestra la pantalla de conexión. Una vez
/// conectada, monta el panel de escritorio con URLs reales por sección.
class WebApp extends ConsumerStatefulWidget {
  const WebApp({super.key});

  @override
  ConsumerState<WebApp> createState() => _WebAppState();
}

class _WebAppState extends ConsumerState<WebApp> {
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    if (!WebSession.hasSession) {
      setState(() => _restoring = false);
      return;
    }
    final client = WebApiClient(
      baseUri: Uri(
        scheme: 'http',
        host: WebSession.host!,
        port: WebSession.port ?? SyncProtocol.defaultPort,
      ),
      token: WebSession.token,
    );
    try {
      await client.getSettings(); // valida el token guardado
      ref.read(webClientProvider.notifier).state = client;
    } catch (_) {
      WebSession.clear();
      client.close();
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(webClientProvider) != null;
    final settings = ref.watch(webSettingsProvider).valueOrNull ?? SettingsDto();
    final override = ref.watch(webThemeModeOverrideProvider);
    final themeMode = override ??
        enumByName(ThemeMode.values, settings.themeMode, ThemeMode.system);
    final seed = Color(settings.seedColorValue);
    final light = AppTheme.light(ColorScheme.fromSeed(seedColor: seed));
    final amoled = ref.watch(webAmoledOverrideProvider) ?? settings.amoled;
    final dark = AppTheme.dark(
      ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
      amoled: amoled,
    );

    const title = 'Finanzas · Escritorio';
    const locales = [Locale('es', 'ES'), Locale('en')];
    const delegates = <LocalizationsDelegate<dynamic>>[
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];

    if (_restoring) {
      return MaterialApp(
        title: title,
        debugShowCheckedModeBanner: false,
        theme: light,
        darkTheme: dark,
        themeMode: themeMode,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    if (connected) {
      return MaterialApp.router(
        title: title,
        debugShowCheckedModeBanner: false,
        theme: light,
        darkTheme: dark,
        themeMode: themeMode,
        locale: const Locale('es', 'ES'),
        supportedLocales: locales,
        localizationsDelegates: delegates,
        routerConfig: ref.watch(webRouterProvider),
      );
    }

    return MaterialApp(
      title: title,
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      themeMode: themeMode,
      locale: const Locale('es', 'ES'),
      supportedLocales: locales,
      localizationsDelegates: delegates,
      home: const WebConnectScreen(),
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
    _host = TextEditingController(
        text: WebSession.host ?? (base.host.isEmpty ? '' : base.host));
    _port = TextEditingController(
        text: '${WebSession.port ?? (base.hasPort ? base.port : SyncProtocol.defaultPort)}');
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
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? SyncProtocol.defaultPort;
    final deviceId = WebSession.deviceId ?? const Uuid().v4();
    final client =
        WebApiClient(baseUri: Uri(scheme: 'http', host: host, port: port));
    try {
      final token = await client.pair(
        pin: _pin.text.trim(),
        deviceId: deviceId,
        displayName: 'Navegador (PC)',
      );
      WebSession.save(
          host: host, port: port, token: token, deviceId: deviceId);
      ref.read(webClientProvider.notifier).state = client;
    } catch (e) {
      client.close();
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
                    'Activa el servidor Wi-Fi en la app del móvil e introduce su '
                    'PIN. Ambos en la misma red.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _host,
                    decoration: const InputDecoration(labelText: 'IP del móvil'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _port,
                          decoration:
                              const InputDecoration(labelText: 'Puerto'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _pin,
                          onSubmitted: (_) => _busy ? null : _connect(),
                          decoration: const InputDecoration(labelText: 'PIN'),
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
