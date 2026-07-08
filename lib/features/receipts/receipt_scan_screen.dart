import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../data/models/enums.dart';
import '../../data/models/receipt.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/merchant_rule_repository.dart';
import '../../data/repositories/receipt_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../shared/widgets/amount_field.dart';
import '../../shared/widgets/entity_picker_field.dart';
import 'duplicate_detector.dart';
import 'ocr_service.dart';
import 'receipt_image_store.dart';

/// Captura una imagen de un ticket, ejecuta OCR y permite editar y guardar los
/// datos detectados (todo editable antes de confirmar). Si se pasa [receiptId],
/// abre un ticket existente en modo edición y sincroniza el gasto vinculado.
class ReceiptScanScreen extends ConsumerStatefulWidget {
  const ReceiptScanScreen({
    super.key,
    this.autoStartCamera = false,
    this.receiptId,
  });

  /// Abre la cámara automáticamente al entrar (útil desde el acceso rápido:
  /// un toque hace la foto y luego se editan los detalles).
  final bool autoStartCamera;

  /// Id del ticket a editar. Si es null, es un ticket nuevo.
  final int? receiptId;

  @override
  ConsumerState<ReceiptScanScreen> createState() => _ReceiptScanScreenState();
}

class _ReceiptScanScreenState extends ConsumerState<ReceiptScanScreen> {
  final _picker = ImagePicker();
  final _merchantController = TextEditingController();

  String? _imagePath;
  bool _imageChanged = false;
  bool _processing = false;
  bool _loading = false;
  String _rawText = '';
  int? _cents;
  DateTime _date = DateTime.now();
  int? _categoryId;
  int? _accountId;
  String? _suggestedCategory;
  bool _createExpense = true;
  Receipt? _existing;

  // Confianza de los campos extraídos: los de baja confianza se resaltan para
  // que el usuario los revise antes de guardar.
  bool _merchantConfident = true;
  bool _totalConfident = true;
  bool _dateDetected = true;

  /// La categoría vino de la memoria de correcciones (comercio ya conocido).
  bool _categoryFromMemory = false;

  bool get _isEditing => _existing != null;

  @override
  void initState() {
    super.initState();
    _init();
    if (widget.autoStartCamera) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pick(ImageSource.camera);
      });
    }
  }

  Future<void> _init() async {
    if (widget.receiptId != null) {
      setState(() => _loading = true);
      final receipt =
          await ref.read(receiptRepositoryProvider).getById(widget.receiptId!);
      if (receipt != null) {
        _existing = receipt;
        _merchantController.text = receipt.merchant;
        _cents = receipt.totalCents;
        _date = receipt.date;
        _categoryId = receipt.categoryId;
        _accountId = receipt.accountId;
        _rawText = receipt.rawText;
        _imagePath = receipt.imagePath.isNotEmpty ? receipt.imagePath : null;
      }
    }
    // Cuenta por defecto: la del ticket o la primera disponible.
    final accounts = await ref.read(accountRepositoryProvider).all();
    _accountId ??= accounts.isNotEmpty ? accounts.first.id : null;
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _merchantController.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 85);
    if (file == null) return;
    setState(() {
      _imagePath = file.path;
      _imageChanged = true;
      _processing = true;
    });
    try {
      final parsed = await ref.read(ocrServiceProvider).processImage(file.path);
      if (!mounted) return;
      setState(() {
        _rawText = parsed.rawText;
        if ((parsed.merchant ?? '').isNotEmpty) {
          _merchantController.text = parsed.merchant!;
        }
        if (parsed.totalCents != null) _cents = parsed.totalCents;
        if (parsed.date != null) _date = parsed.date!;
        _suggestedCategory = parsed.suggestedCategory;
        _merchantConfident = parsed.merchantConfident;
        _totalConfident = parsed.totalConfident && parsed.totalCents != null;
        _dateDetected = parsed.date != null;
      });
      await _applyCategoryHints();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo procesar la imagen: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  /// Resuelve la categoría del ticket: primero la **memoria de correcciones**
  /// (comercio ya visto antes), luego la sugerencia por palabras clave.
  Future<void> _applyCategoryHints() async {
    final merchant = _merchantController.text.trim();
    if (merchant.isNotEmpty) {
      final remembered =
          await ref.read(merchantRuleRepositoryProvider).categoryFor(merchant);
      if (remembered != null && mounted) {
        setState(() {
          _categoryId = remembered;
          _categoryFromMemory = true;
        });
        return;
      }
    }
    _applySuggestedCategory();
  }

  void _applySuggestedCategory() {
    if (_suggestedCategory == null) return;
    final categories = ref.read(categoriesProvider).valueOrNull ?? const [];
    for (final c in categories) {
      if (c.kind == CategoryKind.expense &&
          c.name.toLowerCase() == _suggestedCategory!.toLowerCase()) {
        setState(() => _categoryId = c.id);
        return;
      }
    }
  }

  /// Busca un movimiento existente que coincida con el ticket (mismo importe,
  /// fecha a ±1 día, comercio relacionado) para evitar el doble apunte.
  Future<TransactionModel?> _findDuplicate(int cents, String merchant) async {
    final candidates = await ref.read(transactionRepositoryProvider).query(
          TransactionFilter(
            from: _date.subtract(const Duration(days: 1)),
            to: _date.add(const Duration(days: 2)),
          ),
        );
    return findPossibleDuplicate(
      candidates,
      cents: cents,
      date: _date,
      merchant: merchant,
      excludeId: _existing?.transactionId,
    );
  }

  Future<void> _save() async {
    final cents = _cents;
    if (cents == null || cents <= 0) {
      _toast('Falta el importe.');
      return;
    }
    if (!_isEditing && _imagePath == null) {
      _toast('Falta la imagen.');
      return;
    }

    // Aviso de posible duplicado antes de crear el gasto (p. ej. si ya lo
    // anotó una regla recurrente o se apuntó a mano).
    final merchantForDup = _merchantController.text.trim();
    if (_createExpense && _existing?.transactionId == null) {
      final dup = await _findDuplicate(cents, merchantForDup);
      if (dup != null && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Posible duplicado'),
            content: Text(
              'Ya existe un movimiento "${dup.concept}" con el mismo importe '
              'en fechas cercanas (${DateFormat('d MMM', 'es').format(dup.date)}). '
              '¿Crear el gasto de todas formas?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('No crear gasto'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Crear igualmente'),
              ),
            ],
          ),
        );
        if (proceed == null) return; // cerrado sin decidir: no guardar nada
        if (!proceed) _createExpense = false; // guarda el ticket sin gasto
      }
    }
    if (!mounted) return;

    // Copia la imagen recién elegida a almacenamiento persistente.
    var imagePath = _imagePath ?? '';
    if (_imageChanged && _imagePath != null) {
      imagePath = await persistReceiptImage(_imagePath!);
    }

    final merchant = _merchantController.text.trim();
    final receipt = _existing ?? Receipt();
    receipt
      ..imagePath = imagePath
      ..merchant = merchant
      ..totalCents = cents
      ..date = _date
      ..rawText = _rawText
      ..categoryId = _categoryId
      ..accountId = _accountId;
    final receiptId = await ref.read(receiptRepositoryProvider).save(receipt);

    // Crea o sincroniza el gasto vinculado.
    final txnRepo = ref.read(transactionRepositoryProvider);
    var transactionId = receipt.transactionId;
    if (transactionId != null) {
      final txn = await txnRepo.getById(transactionId);
      if (txn != null) {
        txn
          ..type = TransactionType.expense
          ..amountCents = cents
          ..concept = merchant
          ..date = _date
          ..categoryId = _categoryId
          ..accountId = _accountId ?? txn.accountId
          ..receiptId = receiptId;
        await txnRepo.save(txn);
      } else {
        transactionId = null; // el gasto vinculado ya no existe
      }
    } else if (_createExpense && _accountId != null) {
      final txn = TransactionModel()
        ..type = TransactionType.expense
        ..amountCents = cents
        ..concept = merchant
        ..date = _date
        ..accountId = _accountId!
        ..categoryId = _categoryId
        ..receiptId = receiptId;
      transactionId = await txnRepo.save(txn);
    }

    // Guarda el enlace inverso en el ticket si cambió.
    if (receipt.transactionId != transactionId) {
      receipt.transactionId = transactionId;
      await ref.read(receiptRepositoryProvider).save(receipt);
    }

    // Memoria de correcciones: recuerda comercio → categoría para que el
    // próximo ticket del mismo comercio se categorice solo.
    if (merchant.isNotEmpty && _categoryId != null) {
      await ref
          .read(merchantRuleRepositoryProvider)
          .remember(merchant, _categoryId!);
    }

    if (mounted) Navigator.of(context).pop(true);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final categories = (ref.watch(categoriesProvider).valueOrNull ?? const [])
        .where((c) => c.kind == CategoryKind.expense)
        .toList();
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];

    final showForm = _imagePath != null || _isEditing;
    final hasImageFile =
        _imagePath != null && File(_imagePath!).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar ticket' : 'Escanear ticket'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (hasImageFile)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(File(_imagePath!),
                        height: 200, fit: BoxFit.cover, width: double.infinity),
                  ),
                if (_processing) ...[
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 8),
                  const Center(child: Text('Reconociendo texto…')),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pick(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Cámara'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pick(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Galería'),
                      ),
                    ),
                  ],
                ),
                if (showForm) ...[
                  const SizedBox(height: 20),
                  Text(
                    _isEditing ? 'Datos del ticket' : 'Datos detectados (editables)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _merchantController,
                    onChanged: (_) => _categoryFromMemory = false,
                    decoration: InputDecoration(
                      labelText: 'Comercio',
                      prefixIcon: const Icon(Icons.store),
                      helperText: _merchantConfident
                          ? null
                          : 'Detección dudosa: revísalo',
                      helperStyle: TextStyle(
                          color: Theme.of(context).colorScheme.error),
                      suffixIcon: _merchantConfident
                          ? null
                          : Icon(Icons.warning_amber,
                              color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                  const SizedBox(height: 16),
                  AmountField(
                    initialCents: _cents,
                    label: _totalConfident ? 'Total' : 'Total (dudoso: revísalo)',
                    onChangedCents: (c) => _cents = c,
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      side: BorderSide(
                          color: _dateDetected
                              ? Theme.of(context).colorScheme.outline
                              : Theme.of(context).colorScheme.error),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: const Icon(Icons.calendar_today),
                    title: Text(
                        _dateDetected ? 'Fecha' : 'Fecha (no detectada: revísala)'),
                    trailing:
                        Text(DateFormat('d MMM yyyy', 'es').format(_date)),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => _date = picked);
                    },
                  ),
                  const SizedBox(height: 16),
                  EntityPickerField(
                    items: PickerItem.fromCategories(categories),
                    value: _categoryId,
                    onChanged: (v) => setState(() => _categoryId = v),
                    labelText: 'Categoría',
                    sheetTitle: 'Selecciona categoría',
                    prefixIcon: Icons.category,
                    allowNone: true,
                    helperText: _categoryFromMemory
                        ? 'Recordada de tickets anteriores de este comercio'
                        : (_suggestedCategory != null
                            ? 'Sugerida: $_suggestedCategory'
                            : null),
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
                  if (_existing?.transactionId == null) ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      value: _createExpense,
                      title: const Text('Crear gasto a partir del ticket'),
                      onChanged: (v) => setState(() => _createExpense = v),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save),
                    label: Text(_isEditing ? 'Guardar cambios' : 'Guardar ticket'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
