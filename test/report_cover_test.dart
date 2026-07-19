import 'package:finanzas/data/report_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final from = DateTime(2026, 1, 1);
  final to = DateTime(2026, 12, 31);

  group('ReportOptions.effectiveCoverCards', () {
    test('lista vacía → tarjetas por defecto (portada no queda en blanco)', () {
      final o = ReportOptions(from: from, to: to, coverCards: const []);
      expect(o.effectiveCoverCards, kDefaultReportCoverCards);
    });

    test('lista con contenido se respeta tal cual', () {
      final o = ReportOptions(
        from: from,
        to: to,
        coverCards: const ['kpiIncome', 'kpiExpense'],
      );
      expect(o.effectiveCoverCards, const ['kpiIncome', 'kpiExpense']);
    });

    test('config con coverCards vacío llega a las opciones como vacío pero '
        'effectiveCoverCards lo rescata', () {
      // Simula el estado que dejaba la portada en blanco: el usuario ocultó
      // todas las tarjetas y se persistió coverCards: [].
      const cfg = ReportConfig(coverCards: []);
      final o = cfg.toOptions(from: from, to: to);
      expect(o.coverCards, isEmpty);
      expect(o.effectiveCoverCards, kDefaultReportCoverCards);
    });
  });
}
