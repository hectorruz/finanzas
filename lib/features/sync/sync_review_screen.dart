import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money/money.dart';
import 'model/entity_change.dart';
import 'model/sync_decisions.dart';
import 'model/sync_plan.dart';

/// Datos que recibe la pantalla de revisión: el plan clasificado y el callback
/// que ejecuta la fusión (fase 3 lo conecta con el envío al vinculado).
class SyncReviewArgs {
  SyncReviewArgs({
    required this.plan,
    required this.onConfirm,
    this.peerName = 'el otro dispositivo',
  });

  final SyncPlan plan;
  final String peerName;

  /// Aplica las decisiones (fusión atómica + devolver estado al vinculado).
  final Future<void> Function(SyncDecisions) onConfirm;
}

/// Pantalla de revisión (vive en el admin). Presenta los cambios del vinculado
/// para decisión humana: nada se aplica a ciegas. Menos mágico, pero en una app
/// de dinero es lo correcto.
class SyncReviewScreen extends ConsumerStatefulWidget {
  const SyncReviewScreen({super.key, required this.args});

  final SyncReviewArgs args;

  @override
  ConsumerState<SyncReviewScreen> createState() => _SyncReviewScreenState();
}

class _SyncReviewScreenState extends ConsumerState<SyncReviewScreen> {
  /// Uuids denegados (de nuevos + actualizaciones limpias). Aprobado por defecto.
  final Set<String> _denied = {};

  /// Elección por conflicto; por defecto conserva la versión del admin.
  final Map<String, ConflictChoice> _choices = {};

  bool _busy = false;

  SyncPlan get _plan => widget.args.plan;

  @override
  void initState() {
    super.initState();
    for (final c in _plan.conflicts) {
      _choices[c.uuid] = ConflictChoice.keepLocal;
    }
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      await widget.args.onConfirm(SyncDecisions(
        deniedUuids: {..._denied},
        conflictChoices: {..._choices},
      ));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo sincronizar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final nonConflict = [..._plan.additions, ..._plan.cleanUpdates];

    return Scaffold(
      appBar: AppBar(title: const Text('Revisar sincronización')),
      body: _plan.isEmpty
          ? const _EmptyState()
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                _SummaryCard(plan: _plan, peerName: widget.args.peerName),
                if (_plan.conflicts.isNotEmpty) ...[
                  const _SectionHeader('Conflictos'),
                  for (final c in _plan.conflicts)
                    _ConflictCard(
                      conflict: c,
                      choice: _choices[c.uuid]!,
                      onChoice: (v) => setState(() => _choices[c.uuid] = v),
                    ),
                ],
                if (nonConflict.isNotEmpty) ...[
                  _NonConflictHeader(
                    total: nonConflict.length,
                    deniedCount: _denied.length,
                    onApproveAll: () => setState(_denied.clear),
                    onDenyAll: () => setState(
                        () => _denied.addAll(nonConflict.map((e) => e.uuid))),
                  ),
                  for (final change in nonConflict)
                    _NonConflictTile(
                      change: change,
                      isNew: _plan.additions.contains(change),
                      approved: !_denied.contains(change.uuid),
                      onChanged: (approved) => setState(() {
                        if (approved) {
                          _denied.remove(change.uuid);
                        } else {
                          _denied.add(change.uuid);
                        }
                      }),
                    ),
                ],
              ],
            ),
      bottomNavigationBar: _plan.isEmpty
          ? null
          : SafeArea(
              minimum: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _busy ? null : _confirm,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(_busy ? 'Sincronizando…' : 'Confirmar y sincronizar'),
              ),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            const Text('Todo está al día. No hay cambios que revisar.',
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.plan, required this.peerName});
  final SyncPlan plan;
  final String peerName;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cambios de $peerName',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                _Stat(count: plan.additions.length, label: 'nuevos'),
                _Stat(count: plan.cleanUpdates.length, label: 'actualizaciones'),
                _Stat(
                  count: plan.conflicts.length,
                  label: 'conflictos',
                  highlight: plan.conflicts.isNotEmpty,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.count, required this.label, this.highlight = false});
  final int count;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = highlight ? scheme.error : scheme.onSurface;
    return Expanded(
      child: Column(
        children: [
          Text('$count',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.bold)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(title.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              )),
    );
  }
}

class _NonConflictHeader extends StatelessWidget {
  const _NonConflictHeader({
    required this.total,
    required this.deniedCount,
    required this.onApproveAll,
    required this.onDenyAll,
  });
  final int total;
  final int deniedCount;
  final VoidCallback onApproveAll;
  final VoidCallback onDenyAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text('SIN CONFLICTO ($total)',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    )),
          ),
          TextButton(
            onPressed: deniedCount == 0 ? onDenyAll : onApproveAll,
            child: Text(deniedCount == 0 ? 'Denegar todo' : 'Aprobar todo'),
          ),
        ],
      ),
    );
  }
}

class _NonConflictTile extends StatelessWidget {
  const _NonConflictTile({
    required this.change,
    required this.isNew,
    required this.approved,
    required this.onChanged,
  });
  final EntityChange change;
  final bool isNew;
  final bool approved;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: approved,
      onChanged: (v) => onChanged(v ?? false),
      title: Text(syncSummaryOf(change)),
      subtitle: Text(
        '${syncCollectionLabel(change.collection)} · '
        '${change.isDeleted ? 'borrado' : (isNew ? 'nuevo' : 'actualización')}',
      ),
      secondary: Icon(change.isDeleted
          ? Icons.delete_outline
          : (isNew ? Icons.add_circle_outline : Icons.edit_outlined)),
    );
  }
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({
    required this.conflict,
    required this.choice,
    required this.onChoice,
  });
  final SyncConflict conflict;
  final ConflictChoice choice;
  final ValueChanged<ConflictChoice> onChoice;

  @override
  Widget build(BuildContext context) {
    final keys = {...conflict.local.data.keys, ...conflict.remote.data.keys}
        .toList();
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${syncCollectionLabel(conflict.collection)}: '
              '${syncSummaryOf(conflict.remote)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(width: 96),
                Expanded(
                  child: Text('Este dispositivo',
                      style: Theme.of(context).textTheme.labelSmall),
                ),
                Expanded(
                  child: Text('Otro dispositivo',
                      style: Theme.of(context).textTheme.labelSmall),
                ),
              ],
            ),
            const Divider(height: 8),
            _diffRow(context, 'Estado',
                conflict.local.isDeleted ? 'Borrado' : 'Activo',
                conflict.remote.isDeleted ? 'Borrado' : 'Activo'),
            for (final k in keys)
              _diffRow(
                context,
                syncFieldLabel(k),
                syncFormatValue(k, conflict.local.data[k]),
                syncFormatValue(k, conflict.remote.data[k]),
              ),
            const SizedBox(height: 12),
            SegmentedButton<ConflictChoice>(
              segments: const [
                ButtonSegment(
                    value: ConflictChoice.keepLocal, label: Text('Este')),
                ButtonSegment(
                    value: ConflictChoice.keepRemote, label: Text('Otro')),
              ],
              selected: {choice},
              onSelectionChanged: (s) => onChoice(s.first),
            ),
            if (choice == ConflictChoice.keepRemote)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Se adoptará la versión del otro dispositivo.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.primary)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _diffRow(
      BuildContext context, String label, String local, String remote) {
    final differ = local != remote;
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: differ ? FontWeight.bold : FontWeight.normal,
          color: differ ? scheme.error : null,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(local, style: style)),
          Expanded(child: Text(remote, style: style)),
        ],
      ),
    );
  }
}

// --- Formateo / etiquetas de los campos de dominio ---

String syncCollectionLabel(SyncCollection c) {
  switch (c) {
    case SyncCollection.account:
      return 'Cuenta';
    case SyncCollection.category:
      return 'Categoría';
    case SyncCollection.recurringRule:
      return 'Regla recurrente';
    case SyncCollection.receipt:
      return 'Ticket';
    case SyncCollection.transaction:
      return 'Movimiento';
    case SyncCollection.goal:
      return 'Objetivo';
  }
}

const _labels = <String, String>{
  'name': 'Nombre',
  'concept': 'Concepto',
  'amountCents': 'Importe',
  'totalCents': 'Total',
  'targetCents': 'Objetivo',
  'currentCents': 'Acumulado',
  'monthlyContributionCents': 'Aporte/mes',
  'date': 'Fecha',
  'nextDate': 'Próxima',
  'endDate': 'Fin',
  'deadline': 'Fecha límite',
  'note': 'Nota',
  'type': 'Tipo',
  'kind': 'Tipo',
  'frequency': 'Frecuencia',
  'interval': 'Cada',
  'active': 'Activa',
  'merchant': 'Comercio',
  'rawText': 'Texto OCR',
  'accountUuid': 'Cuenta',
  'toAccountUuid': 'Cuenta destino',
  'categoryUuid': 'Categoría',
  'parentUuid': 'Padre',
  'recurringRuleUuid': 'Regla',
  'receiptUuid': 'Ticket',
  'transactionUuid': 'Movimiento',
  'currency': 'Moneda',
  'iconName': 'Icono',
  'colorValue': 'Color',
  'archived': 'Archivada',
  'includeInTotal': 'En total',
  'isDefault': 'Por defecto',
  'sortOrder': 'Orden',
  'planMode': 'Modo',
  'depositRateBps': 'TAE',
  'depositStartDate': 'Apertura',
  'depositEndDate': 'Vencimiento',
  'depositPayout': 'Liquidación',
  'depositAutoRenew': 'Renovación',
};

String syncFieldLabel(String key) => _labels[key] ?? key;

String syncFormatValue(String key, dynamic value) {
  if (value == null) return '—';
  if (key.endsWith('Cents') && value is int) return Money(value).format();
  if (const {
        'date',
        'nextDate',
        'endDate',
        'deadline',
        'depositStartDate',
        'depositEndDate',
      }.contains(key) &&
      value is String) {
    final d = DateTime.tryParse(value);
    if (d != null) return DateFormat('dd/MM/yyyy').format(d);
  }
  if (key.endsWith('Uuid') && value is String) {
    return value.length > 8 ? '…${value.substring(value.length - 6)}' : value;
  }
  if (value is bool) return value ? 'Sí' : 'No';
  return value.toString();
}

/// Resumen legible de un cambio para el título de la lista.
String syncSummaryOf(EntityChange c) {
  final d = c.data;
  final name = d['name'] ?? d['concept'] ?? d['merchant'];
  final cents = d['amountCents'] ?? d['totalCents'] ?? d['targetCents'];
  final parts = <String>[
    if (name is String && name.isNotEmpty) name,
    if (cents is int) Money(cents).format(),
  ];
  return parts.isEmpty ? c.uuid : parts.join(' · ');
}
