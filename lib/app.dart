import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/notifications/local_notifications.dart';
import 'core/platform/quick_tile.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/settings_repository.dart';
import 'features/security/app_lock_gate.dart';
import 'features/sync/net/sync_foreground_service.dart';
import 'features/sync/sync_service.dart';

class FinanzasApp extends ConsumerStatefulWidget {
  const FinanzasApp({super.key});

  @override
  ConsumerState<FinanzasApp> createState() => _FinanzasAppState();
}

class _FinanzasAppState extends ConsumerState<FinanzasApp>
    with WidgetsBindingObserver {
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Auto-sync al detectar que este dispositivo (vinculado) entra en una Wi-Fi:
    // si el principal está en la misma red, se pone al día solo. Mejor esfuerzo.
    _connSub = Connectivity()
        .onConnectivityChanged
        .listen(_onConnectivityChanged);
    // Acciones recibidas con la app ya abierta (tile vía onNewIntent).
    QuickTile.setActionHandler(_handleQuickAction);
    // Toque de una notificación con la app ya abierta (recordatorio de sync).
    onNotificationTap = _handleNotificationPayload;
    // Señales del servicio en primer plano (botón "Detener servidor" / toque de
    // la notificación persistente del servidor). Corren en otro isolate, así que
    // el principal las recibe por este canal.
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback(_onForegroundTaskData);
    // Arranque en frío: acción del tile o notificación que lanzó la app, una
    // vez montado el router. Y, si este dispositivo es el vinculado, un
    // intento silencioso de ponerse al día con el admin sin que el usuario
    // tenga que entrar a propósito a la pantalla de sync.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final action = await QuickTile.getInitialAction();
      if (action != null) _handleQuickAction(action);
      await _checkNotificationLaunch();
      _tryBackgroundSync();
      await _maybeAutoStartServer();
    });
  }

  /// Si este dispositivo es el principal y tiene activado el auto-inicio, levanta
  /// el servidor al abrir la app sin que haya que pulsar "Activar servidor".
  Future<void> _maybeAutoStartServer() async {
    final s = await ref.read(settingsRepositoryProvider).getOrCreate();
    if (s.syncIsAdmin && s.syncAutoStartServer) {
      await ref.read(syncServerControllerProvider.notifier).start();
    }
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onForegroundTaskData);
    _connSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Señales que llegan desde el isolate del servicio en primer plano
  /// (notificación persistente del servidor).
  void _onForegroundTaskData(Object data) {
    if (data == kSyncStopSignal) {
      ref.read(syncServerControllerProvider.notifier).stop();
    } else if (data == kSyncOpenSettingsSignal) {
      ref.read(routerProvider).push(Routes.serverSettings);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _tryBackgroundSync();
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi)) _tryBackgroundSync();
  }

  void _handleQuickAction(String action) {
    if (action == QuickTile.newMovement) {
      ref.read(routerProvider).push(Routes.movementEditor);
    }
  }

  Future<void> _checkNotificationLaunch() async {
    if (!await ensureNotificationsInitialized()) return;
    final details =
        await localNotificationsPlugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true) {
      _handleNotificationPayload(details?.notificationResponse?.payload);
    }
  }

  void _handleNotificationPayload(String? payload) {
    if (payload == 'sync') ref.read(routerProvider).push(Routes.sync);
  }

  /// Mejor esfuerzo, silencioso: si hay un admin guardado y estamos en su
  /// misma red, se sincroniza solo. Si no es alcanzable ahora mismo, no pasa
  /// nada — el usuario siempre puede entrar a Sincronización y hacerlo a mano.
  void _tryBackgroundSync() {
    if (!ref.read(currentSettingsProvider).syncLinkedAutoSyncEnabled) return;
    unawaited(ref.read(linkedSyncServiceProvider).tryBackgroundSyncAll());
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(currentSettingsProvider);
    final themeMode = ref.watch(themeModeProvider);

    final fallbackSeed = Color(settings.seedColorValue);

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final useDynamic = settings.dynamicColor &&
            lightDynamic != null &&
            darkDynamic != null;

        final lightScheme = useDynamic
            ? lightDynamic
            : ColorScheme.fromSeed(seedColor: fallbackSeed);
        final darkScheme = useDynamic
            ? darkDynamic
            : ColorScheme.fromSeed(
                seedColor: fallbackSeed,
                brightness: Brightness.dark,
              );

        return MaterialApp.router(
          title: 'Finanzas',
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          builder: (context, child) =>
              AppLockGate(child: child ?? const SizedBox.shrink()),
          themeMode: themeMode,
          theme: AppTheme.light(lightScheme),
          darkTheme: AppTheme.dark(darkScheme, amoled: settings.amoled),
          locale: const Locale('es', 'ES'),
          supportedLocales: const [Locale('es', 'ES'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        );
      },
    );
  }
}
