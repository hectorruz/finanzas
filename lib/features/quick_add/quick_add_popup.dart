import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/app_icons.dart';
import '../../data/models/category.dart';
import '../../data/models/enums.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../shared/widgets/amount_field.dart';

/// App mínima y translúcida para el popup de alta rápida (tile de Android).
/// No monta la app completa ni el bloqueo: solo un diálogo para ingreso/gasto.
class QuickAddPopupApp extends StatelessWidget {
  const QuickAddPopupApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2196F3),
        brightness: MediaQuery.platformBrightnessOf(context),
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: const QuickAddPopup(),
    );
  }
}

class QuickAddPopup extends ConsumerStatefulWidget {
  const QuickAddPopup({super.key});

  @override
  ConsumerState<QuickAddPopup> createState() => _QuickAddPopupState();
}

class _QuickAddPopupState extends ConsumerState<QuickAddPopup> {
  TransactionType _type = TransactionType.expense;
  int? _cents;
  int? _accountId;
  int? _categoryId;
  bool _saving = false;
  final _conceptController = TextEditingController();

  @override
  void dispose() {
    _conceptController.dispose();
    super.dispose();
  }

  void _close() => SystemNavigator.pop();

  Future<void> _save(List<dynamic> accounts) async {
    if (_cents == null || _cents! <= 0) return;
    final accountId =
        _accountId ?? (accounts.isNotEmpty ? accounts.first.id as int : null);
    if (accountId == null) return;
    setState(() => _saving = true);
    final txn = TransactionModel()
      ..type = _type
      ..amountCents = _cents!
      ..concept = _conceptController.text.trim()
      ..date = DateTime.now()
      ..accountId = accountId
      ..categoryId = _categoryId;
    await ref.read(transactionRepositoryProvider).save(txn);
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    _accountId ??= accounts.isNotEmpty ? accounts.first.id : null;
    final categories = (ref.watch(categoriesProvider).valueOrNull ?? const [])
        .where((c) =>
            c.kind ==
            (_type == TransactionType.income
                ? CategoryKind.income
                : CategoryKind.expense))
        .toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Scrim: tocar fuera cierra el popup.
          Positioned.fill(
            child: GestureDetector(
              onTap: _close,
              child: Container(color: Colors.black54),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Añadir movimiento',
                              style: theme.textTheme.titleLarge),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: _close,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<TransactionType>(
                        segments: const [
                          ButtonSegment(
                            value: TransactionType.expense,
                            label: Text('Gasto'),
                            icon: Icon(Icons.remove),
                          ),
                          ButtonSegment(
                            value: TransactionType.income,
                            label: Text('Ingreso'),
                            icon: Icon(Icons.add),
                          ),
                        ],
                        selected: {_type},
                        onSelectionChanged: (s) => setState(() {
                          _type = s.first;
                          _categoryId = null;
                        }),
                      ),
                      const SizedBox(height: 16),
                      AmountField(
                        autofocus: true,
                        initialCents: _cents,
                        onChangedCents: (c) => _cents = c,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _conceptController,
                        decoration: const InputDecoration(
                          labelText: 'Concepto (opcional)',
                          prefixIcon: Icon(Icons.notes),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                        value: _accountId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Cuenta',
                          prefixIcon: Icon(Icons.account_balance_wallet),
                        ),
                        items: [
                          for (final a in accounts)
                            DropdownMenuItem<int>(
                              value: a.id,
                              child: Text(a.name),
                            ),
                        ],
                        onChanged: (v) => setState(() => _accountId = v),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                        value: categories.any((c) => c.id == _categoryId)
                            ? _categoryId
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Categoría (opcional)',
                          prefixIcon: Icon(Icons.category),
                        ),
                        items: [
                          for (final g in groupCategories(categories)) ...[
                            _catItem(g.parent, false),
                            for (final sub in g.children) _catItem(sub, true),
                          ],
                        ],
                        onChanged: (v) => setState(() => _categoryId = v),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _saving ? null : () => _save(accounts),
                        icon: const Icon(Icons.check),
                        label: const Text('Guardar'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  DropdownMenuItem<int> _catItem(Category c, bool indent) => DropdownMenuItem<int>(
        value: c.id,
        child: Row(
          children: [
            if (indent) const SizedBox(width: 20),
            Icon(iconByName(c.iconName), size: 18, color: Color(c.colorValue)),
            const SizedBox(width: 8),
            Flexible(child: Text(c.name, overflow: TextOverflow.ellipsis)),
          ],
        ),
      );
}
