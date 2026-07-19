import 'package:flutter/material.dart';

import '../../data/report_cover_cards.dart';
import '../../data/report_service.dart';

/// Editor de las tarjetas de la portada personalizable del informe
/// (`ReportConfig.coverCards`). Reordenable (arrastra para cambiar el orden
/// de aparición) con una lista aparte de tarjetas ocultas para añadir.
///
/// Es un widget sin dependencias de Isar/plataforma a propósito: lo usan
/// tanto la pantalla de informes del móvil (`ReportScreen`) como la de la
/// webapp de escritorio (`WebReportsPage`), que persisten en sitios distintos
/// pero comparten el mismo `ReportConfig`.
class ReportCoverCardsEditor extends StatelessWidget {
  const ReportCoverCardsEditor({
    super.key,
    required this.cards,
    required this.onChanged,
  });

  /// Claves seleccionadas, en orden (vacío = por defecto).
  final List<String> cards;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final visible = (cards.isEmpty ? kDefaultReportCoverCards : cards)
        .where((k) => reportCoverCardByKey(k) != null)
        .toList();
    final hidden = kReportCoverCatalog
        .map((c) => c.key)
        .where((k) => !visible.contains(k))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Elige qué métricas, gráficos y análisis muestra la portada, y en '
            'qué orden. Arrastra para reordenar.',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          onReorder: (oldIndex, newIndex) {
            final list = [...visible];
            if (newIndex > oldIndex) newIndex--;
            final item = list.removeAt(oldIndex);
            list.insert(newIndex, item);
            onChanged(list);
          },
          children: [
            for (final key in visible)
              ListTile(
                key: ValueKey(key),
                dense: true,
                leading: Icon(reportCoverCardByKey(key)?.icon ?? Icons.dashboard),
                title: Text(reportCoverCardLabel(key)),
                trailing: IconButton(
                  icon: const Icon(Icons.visibility_off_outlined),
                  tooltip: 'Ocultar',
                  onPressed: () =>
                      onChanged(visible.where((k) => k != key).toList()),
                ),
              ),
          ],
        ),
        if (hidden.isNotEmpty) ...[
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text('Ocultas'),
          ),
          for (final key in hidden)
            ListTile(
              dense: true,
              leading: Icon(reportCoverCardByKey(key)?.icon ?? Icons.dashboard),
              title: Text(reportCoverCardLabel(key)),
              trailing: IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Mostrar',
                onPressed: () => onChanged([...visible, key]),
              ),
            ),
        ],
      ],
    );
  }
}
