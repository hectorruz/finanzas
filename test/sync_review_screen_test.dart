import 'package:finanzas/features/sync/model/entity_change.dart';
import 'package:finanzas/features/sync/model/sync_decisions.dart';
import 'package:finanzas/features/sync/model/sync_plan.dart';
import 'package:finanzas/features/sync/sync_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// La pantalla de revisión traduce lo que toca la persona en un [SyncDecisions]
/// correcto y nunca aplica nada por su cuenta.
void main() {
  EntityChange tx(String uuid, int cents, {DateTime? updated}) => EntityChange(
        collection: SyncCollection.transaction,
        uuid: uuid,
        updatedAt: updated ?? DateTime(2026, 2, 1),
        deletedAt: null,
        data: {'concept': 'Mov $uuid', 'amountCents': cents},
      );

  testWidgets('deniega un alta y elige la versión remota en un conflicto',
      (tester) async {
    final plan = SyncPlan(
      additions: [tx('add', 100)],
      cleanUpdates: [tx('upd', 200)],
      conflicts: [
        SyncConflict(
          local: tx('con', 300, updated: DateTime(2026, 2, 2)),
          remote: tx('con', 400, updated: DateTime(2026, 2, 3)),
        ),
      ],
    );

    SyncDecisions? captured;
    final args = SyncReviewArgs(
      plan: plan,
      peerName: 'móvil de prueba',
      onConfirm: (d) async => captured = d,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.push(
                    ctx,
                    MaterialPageRoute(
                        builder: (_) => SyncReviewScreen(args: args)),
                  ),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    // Resumen visible.
    expect(find.textContaining('móvil de prueba'), findsOneWidget);

    final scrollable = find.byType(Scrollable).first;

    // En el conflicto, elegir "Otro" (versión remota).
    await tester.scrollUntilVisible(find.text('Otro'), 200,
        scrollable: scrollable);
    await tester.tap(find.text('Otro'));
    await tester.pump();

    // Denegar el alta tocando su fila.
    await tester.scrollUntilVisible(find.textContaining('Mov add'), 200,
        scrollable: scrollable);
    await tester.tap(find.textContaining('Mov add'));
    await tester.pump();

    // Confirmar.
    await tester.tap(find.text('Confirmar y sincronizar'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.deniedUuids, contains('add'));
    expect(captured!.deniedUuids, isNot(contains('upd')));
    expect(captured!.choiceFor('con'), ConflictChoice.keepRemote);
  });
}
