import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/platform/quick_tile.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/settings_repository.dart';
import 'features/security/app_lock_gate.dart';

class FinanzasApp extends ConsumerStatefulWidget {
  const FinanzasApp({super.key});

  @override
  ConsumerState<FinanzasApp> createState() => _FinanzasAppState();
}

class _FinanzasAppState extends ConsumerState<FinanzasApp> {
  @override
  void initState() {
    super.initState();
    // Acciones recibidas con la app ya abierta (tile vía onNewIntent).
    QuickTile.setActionHandler(_handleQuickAction);
    // Acción del arranque en frío, una vez montado el router.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final action = await QuickTile.getInitialAction();
      if (action != null) _handleQuickAction(action);
    });
  }

  void _handleQuickAction(String action) {
    if (action == QuickTile.newMovement) {
      ref.read(routerProvider).push(Routes.movementEditor);
    }
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
