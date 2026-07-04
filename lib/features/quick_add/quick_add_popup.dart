import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/enums.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../shared/widgets/amount_field.dart';
import '../../shared/widgets/entity_picker_field.dart';
import '../receipts/receipt_scan_screen.dart';

/// App mínima y translúcida para el popup de alta rápida (tile de Android).
/// No monta la app completa ni el bloqueo: solo un diálogo para ingreso/gasto.
/// Reutiliza el mismo esquema de color/tema que la app (Material You, color
/// semilla, AMOLED y modo claro/oscuro) leyendo los ajustes guardados.
class QuickAddPopupApp extends ConsumerWidget {
  const QuickAddPopupApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          color: Colors.transparent,
          themeMode: themeMode,
          theme: AppTheme.light(lightScheme),
          darkTheme: AppTheme.dark(darkScheme, amoled: settings.amoled),
          home: const QuickAddPopup(),
        );
      },
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

  /// Abre el escáner de tickets (hace la foto y permite editar los detalles).
  /// Si se guarda un ticket, cierra el popup.
  Future<void> _scanReceipt() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const ReceiptScanScreen(autoStartCamera: true),
      ),
    );
    if (saved == true) _close();
  }

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
                      EntityPickerField(
                        items: PickerItem.fromAccounts(accounts),
                        value: _accountId,
                        onChanged: (v) => setState(() => _accountId = v),
                        labelText: 'Cuenta',
                        sheetTitle: 'Selecciona cuenta',
                        prefixIcon: Icons.account_balance_wallet,
                      ),
                      const SizedBox(height: 16),
                      EntityPickerField(
                        items: PickerItem.fromCategories(categories),
                        value: _categoryId,
                        onChanged: (v) => setState(() => _categoryId = v),
                        labelText: 'Categoría (opcional)',
                        sheetTitle: 'Selecciona categoría',
                        prefixIcon: Icons.category,
                        allowNone: true,
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
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _scanReceipt,
                        icon: const Icon(Icons.receipt_long),
                        label: const Text('Escanear ticket'),
                        style: OutlinedButton.styleFrom(
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
}
