import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/enums.dart';
import '../data/repositories/settings_repository.dart';
import 'dashboard/dashboard_screen.dart';
import 'movements/movements_screen.dart';
import 'receipts/receipts_screen.dart';
import 'settings/goals_screen.dart';
import 'settings/settings_screen.dart';

/// Contenedor principal con barra inferior de navegación.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(currentSettingsProvider);
    final tabs = [for (final s in settings.sections) _tabFor(s)];

    // Mantener el índice dentro de rango si cambia el número de pestañas.
    final index = _index.clamp(0, tabs.length - 1);

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [for (final t in tabs) t.screen],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        labelBehavior: settings.alwaysShowNavLabels
            ? NavigationDestinationLabelBehavior.alwaysShow
            : NavigationDestinationLabelBehavior.onlyShowSelected,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [for (final t in tabs) t.destination],
      ),
    );
  }

  _Tab _tabFor(NavSection section) => switch (section) {
        NavSection.dashboard => const _Tab(
            screen: DashboardScreen(),
            destination: NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Inicio',
            ),
          ),
        NavSection.movements => const _Tab(
            screen: MovementsScreen(),
            destination: NavigationDestination(
              icon: Icon(Icons.swap_vert_outlined),
              selectedIcon: Icon(Icons.swap_vert),
              label: 'Movimientos',
            ),
          ),
        NavSection.receipts => const _Tab(
            screen: ReceiptsScreen(),
            destination: NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Tickets',
            ),
          ),
        NavSection.goals => const _Tab(
            screen: GoalsScreen(),
            destination: NavigationDestination(
              icon: Icon(Icons.flag_outlined),
              selectedIcon: Icon(Icons.flag),
              label: 'Objetivos',
            ),
          ),
        NavSection.settings => const _Tab(
            screen: SettingsScreen(),
            destination: NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Ajustes',
            ),
          ),
      };
}

class _Tab {
  const _Tab({required this.screen, required this.destination});
  final Widget screen;
  final NavigationDestination destination;
}
