import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money/money.dart';
import '../../data/models/enums.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/transaction_repository.dart';

/// Hoja inferior para configurar el filtro de movimientos (tipo Excel).
class MovementsFilterSheet extends ConsumerStatefulWidget {
  const MovementsFilterSheet({super.key});

  @override
  ConsumerState<MovementsFilterSheet> createState() =>
      _MovementsFilterSheetState();
}

class _MovementsFilterSheetState extends ConsumerState<MovementsFilterSheet> {
  late TransactionFilter _draft;
  final _queryController = TextEditingController();
  final _minController = TextEditingController();
  final _maxController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _draft = ref.read(transactionFilterProvider);
    _queryController.text = _draft.query;
    if (_draft.minCents != null) {
      _minController.text = (_draft.minCents! / 100).toStringAsFixed(2);
    }
    if (_draft.maxCents != null) {
      _maxController.text = (_draft.maxCents! / 100).toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  void _apply() {
    final filter = _draft.copyWith(
      query: _queryController.text,
      minCents: Money.parseToCents(_minController.text),
      maxCents: Money.parseToCents(_maxController.text),
      clearAmounts:
          _minController.text.isEmpty && _maxController.text.isEmpty,
    );
    ref.read(transactionFilterProvider.notifier).state = filter;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Filtros',
                  style: Theme.of(context).textTheme.titleLarge),
              TextButton(
                onPressed: () {
                  setState(() => _draft = const TransactionFilter());
                  _queryController.clear();
                  _minController.clear();
                  _maxController.clear();
                },
                child: const Text('Restablecer'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _queryController,
            decoration: const InputDecoration(
              labelText: 'Buscar concepto o nota',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 16),
          _label('Tipo'),
          Wrap(
            spacing: 8,
            children: [
              for (final t in TransactionType.values)
                FilterChip(
                  label: Text(_typeLabel(t)),
                  selected: _draft.types.contains(t),
                  onSelected: (sel) => setState(() {
                    final types = {..._draft.types};
                    sel ? types.add(t) : types.remove(t);
                    _draft = _draft.copyWith(types: types);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _label('Cuentas'),
          Wrap(
            spacing: 8,
            children: [
              for (final a in accounts)
                FilterChip(
                  label: Text(a.name),
                  selected: _draft.accountIds.contains(a.id),
                  onSelected: (sel) => setState(() {
                    final ids = {..._draft.accountIds};
                    sel ? ids.add(a.id) : ids.remove(a.id);
                    _draft = _draft.copyWith(accountIds: ids);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _label('Categorías'),
          Wrap(
            spacing: 8,
            children: [
              for (final g in groupCategories(categories)) ...[
                for (final c in [g.parent, ...g.children])
                  FilterChip(
                    label: Text(c.parentId == null ? c.name : '› ${c.name}'),
                    selected: _draft.categoryIds.contains(c.id),
                    onSelected: (sel) => setState(() {
                      final ids = {..._draft.categoryIds};
                      sel ? ids.add(c.id) : ids.remove(c.id);
                      _draft = _draft.copyWith(categoryIds: ids);
                    }),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          _label('Importe (€)'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _minController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Mín'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _maxController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Máx'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _label('Fechas'),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(_draft.from == null
                      ? 'Desde'
                      : DateFormat('d/M/yy').format(_draft.from!)),
                  onPressed: () => _pickDate(true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event, size: 16),
                  label: Text(_draft.to == null
                      ? 'Hasta'
                      : DateFormat('d/M/yy').format(_draft.to!)),
                  onPressed: () => _pickDate(false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _label('Ordenar por'),
          DropdownButtonFormField<TransactionSort>(
            value: _draft.sort,
            items: const [
              DropdownMenuItem(
                  value: TransactionSort.dateDesc,
                  child: Text('Fecha (reciente primero)')),
              DropdownMenuItem(
                  value: TransactionSort.dateAsc,
                  child: Text('Fecha (antigua primero)')),
              DropdownMenuItem(
                  value: TransactionSort.amountDesc,
                  child: Text('Importe (mayor primero)')),
              DropdownMenuItem(
                  value: TransactionSort.amountAsc,
                  child: Text('Importe (menor primero)')),
            ],
            onChanged: (v) => setState(
                () => _draft = _draft.copyWith(sort: v)),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _apply,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Aplicar filtros'),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.w600)),
      );

  String _typeLabel(TransactionType t) => switch (t) {
        TransactionType.income => 'Ingresos',
        TransactionType.expense => 'Gastos',
        TransactionType.transfer => 'Transferencias',
      };

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _draft.from : _draft.to) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _draft = isFrom
            ? _draft.copyWith(from: picked)
            : _draft.copyWith(
                to: DateTime(picked.year, picked.month, picked.day, 23, 59, 59),
              );
      });
    }
  }
}
