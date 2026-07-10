import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../web_providers.dart';
import '../widgets/web_ui.dart';
import 'web_calendar_view.dart';

/// Página de calendario de movimientos (extra de escritorio).
class WebCalendarPage extends ConsumerWidget {
  const WebCalendarPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return WebPage(
      title: 'Calendario',
      subtitle: 'Movimientos por día',
      actions: [
        IconButton(
          tooltip: 'Refrescar',
          icon: const Icon(Icons.refresh),
          onPressed: () => bumpWebRefresh(ref),
        ),
      ],
      child: const WebCalendarView(),
    );
  }
}
