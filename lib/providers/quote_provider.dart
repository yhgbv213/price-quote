// lib/providers/quote_provider.dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../db/quote_dao.dart';
import '../db/quote_item_dao.dart';
import '../models/quote.dart';
import '../models/quote_item.dart';
import '../models/product.dart';
import '../utils/constants.dart';

class QuoteProvider extends ChangeNotifier {
  final QuoteDao _quoteDao = QuoteDao();
  final QuoteItemDao _itemDao = QuoteItemDao();

  // ============ 内存状态 ============
  Quote? _draft;
  List<QuoteItem> _items = [];
  Timer? _debounceTimer;
  bool _loading = false;
  bool _saving = false;
  bool _nameUserEdited = false;

  // ============ Getters ============
  Quote? get draft => _draft;
  List<QuoteItem> get items => List.unmodifiable(_items);
  bool get isLoading => _loading;
  bool get isSaving => _saving;
  int get itemCount => _draft?.itemCount ?? 0;
  double get totalPrice => _draft?.totalPrice ?? 0;
  int get lineCount => _items.length;
  bool get isEmpty => _items.isEmpty;

  // ============ 加载 / 创建草稿 ============
  Future<void> loadOrCreateDraft() async {
    if (_loading) return;
    _loading = true;
    try {
      _draft = await _quoteDao.getDraft();
      if (_draft == null) {
        final id = await _quoteDao.createDraft();
        final now = DateTime.now().millisecondsSinceEpoch;
        _draft = Quote(id: id, createdAt: now, updatedAt: now);
        _items = [];
      } else {
        _items = await _itemDao.getByQuoteId(_draft!.id!);
      }
      _nameUserEdited = _draft!.name != null;
      _recalcTotals();
      notifyListeners();
    } finally {
      _loading = false;
    }
  }

  // ============ 添加商品（扫码/搜索） ============
  Future<void> addProduct(Product product) async {
    if (_draft == null) await loadOrCreateDraft();
    final idx = _items.indexWhere((it) => it.barcode == product.barcode);
    if (idx >= 0) {
      final old = _items[idx];
      _items[idx] = old.copyWith(
        quantity: old.quantity + 1,
        subtotal: old.unitPrice * (old.quantity + 1),
      );
    } else {
      _items.add(
        QuoteItem(
          quoteId: _draft!.id!,
          barcode: product.barcode,
          name: product.name,
          spec: product.spec,
          unitPrice: product.sellingPrice,
          quantity: 1,
          subtotal: product.sellingPrice,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    _recalcTotals();
    notifyListeners();
    _scheduleSave();
  }

  // ============ 数量 +1 ============
  void increment(int index) {
    if (index < 0 || index >= _items.length) return;
    final old = _items[index];
    if (old.quantity >= 9999) return;
    _items[index] = old.copyWith(
      quantity: old.quantity + 1,
      subtotal: old.unitPrice * (old.quantity + 1),
    );
    _recalcTotals();
    notifyListeners();
    _scheduleSave();
  }

  // ============ 数量 -1 ============
  void decrement(int index) {
    if (index < 0 || index >= _items.length) return;
    final old = _items[index];
    if (old.quantity <= 1) return;
    _items[index] = old.copyWith(
      quantity: old.quantity - 1,
      subtotal: old.unitPrice * (old.quantity - 1),
    );
    _recalcTotals();
    notifyListeners();
    _scheduleSave();
  }

  // ============ 设置数量（手动输入） ============
  void setQuantity(int index, int quantity) {
    if (index < 0 || index >= _items.length) return;
    final q = quantity.clamp(1, 9999);
    final old = _items[index];
    _items[index] = old.copyWith(quantity: q, subtotal: old.unitPrice * q);
    _recalcTotals();
    notifyListeners();
    _scheduleSave();
  }

  // ============ 移除一行 ============
  void removeAt(int index) {
    if (index < 0 || index >= _items.length) return;
    _items.removeAt(index);
    _recalcTotals();
    notifyListeners();
    _scheduleSave();
  }

  // ============ 修改客户/备注/名称 ============
  void setCustomer(String? v) {
    if (_draft == null) return;
    _draft = _draft!.copyWith(customer: v);
    notifyListeners();
    _scheduleSave();
  }

  void setNote(String? v) {
    if (_draft == null) return;
    _draft = _draft!.copyWith(note: v);
    notifyListeners();
    _scheduleSave();
  }

  void setName(String? v) {
    if (_draft == null) return;
    _draft = _draft!.copyWith(name: v);
    _nameUserEdited = true;
    notifyListeners();
    _scheduleSave();
  }

  // ============ 保存为正式报价单 ============
  Future<String?> saveAsOfficial() async {
    if (_draft == null) return '草稿未加载';
    if (_items.isEmpty) return '报价单为空，无法保存';

    _saving = true;
    notifyListeners();
    try {
      String finalName;
      if (_nameUserEdited && (_draft!.name?.trim().isNotEmpty ?? false)) {
        finalName = _draft!.name!;
      } else {
        final now = DateTime.now();
        finalName =
            '报价单 ${now.year}${_p(now.month)}${_p(now.day)} ${_p(now.hour)}:${_p(now.minute)}';
      }

      _debounceTimer?.cancel();
      final updatedDraft = _draft!.copyWith(name: finalName);
      await _quoteDao.replaceDraftWithItems(quote: updatedDraft, items: _items);
      await _quoteDao.markAsSaved(_draft!.id!, name: finalName);
      await _enforceLimit();

      // 清空内存 3 处
      _draft = null;
      _items = [];
      _nameUserEdited = false;
      notifyListeners();
      return null;
    } catch (e) {
      return '保存失败: $e';
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  // ============ 清空当前单 ============
  Future<void> clearCurrentDraft() async {
    _debounceTimer?.cancel();
    if (_draft?.id != null) {
      await _quoteDao.deleteQuote(_draft!.id!);
    }
    final id = await _quoteDao.createDraft();
    final now = DateTime.now().millisecondsSinceEpoch;
    _draft = Quote(id: id, createdAt: now, updatedAt: now);
    _items = [];
    _nameUserEdited = false;
    notifyListeners();
  }

  // ============ 立即写入（页面退出时调用） ============
  Future<void> flushNow() async {
    _debounceTimer?.cancel();
    await _flushToDb();
  }

  // ============ 内部：debounce 调度 ============
  void _scheduleSave() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: AppConstants.debounceMs), () {
      _flushToDb();
    });
  }

  // ============ 内部：真正写入 ============
  Future<void> _flushToDb() async {
    if (_draft == null) return;
    try {
      await _quoteDao.replaceDraftWithItems(quote: _draft!, items: _items);
    } catch (e) {
      if (AppConstants.kApiDebug) {
        debugPrint('[QuoteProvider] 草稿保存失败: $e');
      }
    }
  }

  // ============ 内部：汇总 ============
  void _recalcTotals() {
    if (_draft == null) return;
    double total = 0;
    int count = 0;
    for (final it in _items) {
      total += it.subtotal;
      count += it.quantity;
    }
    _draft = _draft!.copyWith(
      totalPrice: double.parse(total.toStringAsFixed(2)),
      itemCount: count,
    );
  }

  // ============ 内部：500 条上限 ============
  Future<void> _enforceLimit() async {
    const maxCount = AppConstants.quoteMaxCount;
    final count = await _quoteDao.countSaved();
    if (count <= maxCount) return;
    final needDelete = count - maxCount;
    final oldOnes = await _quoteDao.getOldestSaved(needDelete);
    for (final q in oldOnes) {
      await _quoteDao.deleteQuote(q.id!);
    }
  }

  String _p(int n) => n.toString().padLeft(2, '0');

  @override
  void dispose() {
    _debounceTimer?.cancel();
    if (_draft != null) {
      _flushToDb();
    }
    super.dispose();
  }
}
