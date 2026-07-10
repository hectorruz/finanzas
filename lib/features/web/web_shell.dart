import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'web_providers.dart';
import 'web_router.dart';
import 'web_session.dart';

/// Chrome de escritorio: barra superior + barra lateral persistente + área de
/// contenido. Responsive: barra lateral ancha con etiquetas, rail compacto de
/// iconos, o cajón (drawer) según el ancho de la ventana.
class WebShell extends ConsumerWidget {
  const WebShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1080;
      final medium = constraints.maxWidth >= 760;
      final useDrawer = !wide && !medium;

      return Scaffold(
        drawer: useDrawer
            ? Drawer(
                child: SafeArea(
                  child: _Sidebar(location: location, expanded: true),
                ),
              )
            : null,
        body: Column(
          children: [
            _TopBar(showMenu: useDrawer),
            const Divider(height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!useDrawer) ...[
                    _Sidebar(location: location, expanded: wide),
                    const VerticalDivider(width: 1),
                  ],
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _TopBar extends ConsumerStatefulWidget {
  const _TopBar({required this.showMenu});
  final bool showMenu;

  @override
  ConsumerState<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends ConsumerState<_TopBar> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _search(String value) {
    ref.read(webTxFilterProvider.notifier).update((f) => f.copyWith(query: value));
    if (GoRouterState.of(context).uri.path != WebRoutes.movements) {
      context.go(WebRoutes.movements);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hide = ref.watch(webHideAmountsProvider);
    return Material(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (widget.showMenu)
              Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
            Icon(Icons.account_balance_wallet, color: scheme.primary),
            const SizedBox(width: 10),
            Text('Finanzas',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(width: 24),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      hintText: 'Buscar movimientos…  (pulsa /)',
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: _search,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: hide ? 'Mostrar importes' : 'Ocultar importes',
              icon: Icon(hide ? Icons.visibility_off : Icons.visibility),
              onPressed: () => ref
                  .read(webHideAmountsProvider.notifier)
                  .update((v) => !v),
            ),
            _ThemeMenuButton(),
            _OverflowMenu(),
          ],
        ),
      ),
    );
  }
}

class _ThemeMenuButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final override = ref.watch(webThemeModeOverrideProvider);
    final isDark = override == ThemeMode.dark ||
        (override == null &&
            Theme.of(context).brightness == Brightness.dark);
    return IconButton(
      tooltip: 'Cambiar tema',
      icon: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
      onPressed: () => ref.read(webThemeModeOverrideProvider.notifier).state =
          isDark ? ThemeMode.light : ThemeMode.dark,
    );
  }
}

class _OverflowMenu extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Más',
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        if (value == 'disconnect') _disconnect(context, ref);
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'host',
          enabled: false,
          child: Text('Conectado a ${WebSession.host ?? '—'}'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'disconnect',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout),
            title: Text('Desconectar'),
          ),
        ),
      ],
    );
  }

  void _disconnect(BuildContext context, WidgetRef ref) {
    WebSession.clear();
    ref.read(webClientProvider)?.close();
    ref.read(webClientProvider.notifier).state = null;
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.location, required this.expanded});

  final String location;
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final width = expanded ? 232.0 : 76.0;

    // Agrupa las secciones por su `group`, conservando el orden.
    final groups = <String, List<WebNavItem>>{};
    for (final item in webNavItems) {
      (groups[item.group] ??= []).add(item);
    }

    return Container(
      width: width,
      color: scheme.surface,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          for (final entry in groups.entries) ...[
            if (expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 16, 6),
                child: Text(
                  entry.key.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.outline,
                        letterSpacing: 0.8,
                      ),
                ),
              )
            else
              const SizedBox(height: 12),
            for (final item in entry.value)
              _NavTile(
                item: item,
                expanded: expanded,
                selected: location == item.route,
              ),
          ],
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.expanded,
    required this.selected,
  });

  final WebNavItem item;
  final bool expanded;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;

    void go() {
      if (Scaffold.maybeOf(context)?.hasDrawer ?? false) {
        Navigator.maybePop(context); // cerrar el drawer en móvil/estrecho
      }
      context.go(item.route);
    }

    final tile = Padding(
      padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 10, vertical: 3),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: go,
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: expanded ? 14 : 0, vertical: 12),
            child: expanded
                ? Row(
                    children: [
                      Icon(item.icon, size: 22, color: fg),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(item.label,
                            style: TextStyle(
                                color: fg,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400)),
                      ),
                    ],
                  )
                : Center(child: Icon(item.icon, size: 24, color: fg)),
          ),
        ),
      ),
    );

    return expanded ? tile : Tooltip(message: item.label, child: tile);
  }
}
