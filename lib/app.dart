import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/settings_repository.dart';

class FinanzasApp extends ConsumerWidget {
  const FinanzasApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
