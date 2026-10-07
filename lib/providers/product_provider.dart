// lib/providers/product_provider.dart
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../db/product_dao.dart';
import '../db/recycle_dao.dart';
import '../db/price_history_dao.dart';
import '../db/app_settings_dao.dart';
import '../models/product.dart';
import '../models/recycle_item.dart';
import '../services/image_service.dart';
import '../utils/constants.dart';

class ProductProvider extends ChangeNotifier {
  final ProductDao _dao = ProductDao();
  final RecycleDao _recycleDao = RecycleDao();
  final PriceHistoryDao _historyDao = PriceHistoryDao();
  final AppSettingsDao _settingsDao = AppSettingsDao();
  final ImageService _imageService = ImageService();

  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  String _searchKeyword = '';
  String _selectedCategory = '全部';
  int _recycleCount = 0;
  String _sortMode = AppConstants.defaultSortMode; // 默认排序

  static const List<String> presetCategories = [
    '全部',
    '未分类',
    '烟',
    '酒',
    '饮料',
    '零食',
    '日用品',
    '其他',
    '手动录入',
  ];

  // 排序选项（值 + 显示名）
  // 3 个排序字段（方向由 sortMode 决定）
  static const List<Map<String, String>> sortFields = [
    {'field': 'update_time', 'label': '时间'},
    {'field': 'price', 'label': '价格'},
    {'field': 'name', 'label': '名称'},
  ];

  // 当前排序的字段（'update_time' / 'price' / 'name'）
  String get sortField {
    if (_sortMode.startsWith('price')) return 'price';
    if (_sortMode.startsWith('name')) return 'name';
    return 'update_time';
  }

  // 当前排序是否降序
  bool get sortDesc {
    return _sortMode.endsWith('_desc');
  }

  // 切换某字段：已是当前字段则反向，否则切到该字段（默认降序）
  Future<void> toggleSort(String field) async {
    String newMode;
    if (sortField == field) {
      // 已选中 → 反向
      newMode = sortDesc ? '${field}_asc' : '${field}_desc';
    } else {
      // 切到新字段 → 默认降序
      newMode = '${field}_desc';
    }
    await setSortMode(newMode);
  }

  // ============ Getters ============
  List<Product> get products => _filteredProducts;
  List<Product> get allProducts => _allProducts;
  String get searchKeyword => _searchKeyword;

  /// 当前搜索是否为"条码式"输入（纯数字且 ≥4 位）
  bool get isBarcodeSearch {
    final kw = _searchKeyword.trim();
    return kw.length >= 4 && int.tryParse(kw) != null;
  }
  String get selectedCategory => _selectedCategory;
  int get recycleCount => _recycleCount;
  String get sortMode => _sortMode;

  // 当前筛选结果的数量
  int get totalCount => _filteredProducts.length;

  // 当前筛选结果的总价值
  double get totalValue {
    double sum = 0;
    for (final p in _filteredProducts) {
      sum += p.sellingPrice;
    }
    return sum;
  }

  // ============ 加载 ============
  Future<void> loadProducts() async {
    // 性能观测：全量加载耗时与条数（用于判断是否需要改分批加载）
    final sw = Stopwatch()..start();
    _allProducts = await _dao.getAllProducts();
    _sortMode =
        await _settingsDao.get('sort_mode') ?? AppConstants.defaultSortMode;
    sw.stop();
    if (AppConstants.kApiDebug) {
      debugPrint(
        '[性能] 加载 ${_allProducts.length} 条商品耗时 ${sw.elapsedMilliseconds}ms',
      );
    }
    _applyFilter();
    await refreshRecycleCount();
    notifyListeners();
  }

  // ============ 排序 ============
  Future<void> setSortMode(String mode) async {
    _sortMode = mode;
    await _settingsDao.set('sort_mode', mode);
    _applyFilter();
    notifyListeners();
  }

  // ============ 保存新商品 ============
  Future<String> saveNewProduct({
    required String barcode,
    required String name,
    String? brand,
    String? spec,
    required String category,
    required double sellingPrice,
    File? pendingImageFile,
  }) async {
    String finalBarcode = barcode.trim();

    if (finalBarcode.isEmpty) {
      finalBarcode = await _allocateAutoBarcode();
    }

    // 处理图片
    String? imagePath;
    String imageSource = 'none';
    if (pendingImageFile != null) {
      imagePath = await _imageService.saveProductImage(
        barcode: finalBarcode,
        source: pendingImageFile,
      );
      if (imagePath != null) imageSource = 'manual';
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final product = Product(
      barcode: finalBarcode,
      name: name,
      brand: brand,
      spec: spec,
      category: category,
      sellingPrice: sellingPrice,
      localImagePath: imagePath,
      imageSource: imageSource,
      updateTime: now,
    );

    await _dao.insertProduct(product);
    await _historyDao.insert(barcode: finalBarcode, price: sellingPrice);
    await loadProducts();
    return finalBarcode;
  }

  // ============ 更新商品 ============
  Future<void> updateProduct(
    Product product, {
    File? pendingImageFile,
    bool deleteImage = false,
  }) async {
    String? finalImagePath = product.localImagePath;
    String imageSource = product.imageSource;

    if (deleteImage) {
      if (product.localImagePath != null) {
        await _imageService.deleteProductImage(product.localImagePath);
      }
      finalImagePath = null;
      imageSource = 'none';
    } else if (pendingImageFile != null) {
      final newPath = await _imageService.saveProductImage(
        barcode: product.barcode,
        source: pendingImageFile,
      );
      if (newPath != null) {
        finalImagePath = newPath;
        imageSource = 'manual';
      }
    }

    final updated = Product(
      id: product.id,
      barcode: product.barcode,
      name: product.name,
      brand: product.brand,
      spec: product.spec,
      category: product.category,
      sellingPrice: product.sellingPrice,
      localImagePath: finalImagePath,
      imageSource: imageSource,
      updateTime: DateTime.now().millisecondsSinceEpoch,
    );

    await _dao.updateProduct(updated);
    await _historyDao.insert(
      barcode: product.barcode,
      price: product.sellingPrice,
    );
    await loadProducts();
  }

  // ============ 上次价 ============
  Future<double?> getLastPrice(String barcode) async {
    if (barcode.trim().isEmpty) return null;
    return await _historyDao.getLatestPrice(barcode.trim());
  }

  // ============ 分配 AUTO_N ============
  Future<String> _allocateAutoBarcode() async {
    const prefix = AppConstants.autoBarcodePrefix;
    final all = await _dao.getAllProducts();
    final used = <int>{};
    for (final p in all) {
      if (p.barcode.startsWith(prefix)) {
        final n = int.tryParse(p.barcode.substring(prefix.length));
        if (n != null) used.add(n);
      }
    }
    int candidate = 1;
    while (used.contains(candidate)) {
      candidate++;
    }
    return '$prefix$candidate';
  }

  // ============ 回收站 ============
  Future<void> refreshRecycleCount() async {
    _recycleCount = await _recycleDao.count();
    notifyListeners();
  }

  Future<void> moveToRecycleBin(Product product) async {
    await _dao.deleteProductById(product.id!);
    await _recycleDao.insert(RecycleItem.fromProduct(product));
    await loadProducts();
    await refreshRecycleCount();
  }

  Future<List<RecycleItem>> loadRecycleItems() async {
    return await _recycleDao.getAll();
  }

  /// 从回收站恢复商品，返回恢复后的条码。
  ///
  /// 条码已被占用时：
  /// - AUTO_ 序号且 [assignNewBarcodeIfConflict] 为 true → 分配新序号（文档 6.4 场景 C）
  /// - 其余情况抛 [StateError]，由调用方提示用户（文档 6.1「冲突时强提示」）
  ///
  /// 注意：默认不自动改号——是否换号由界面询问用户后决定。
  Future<String> restoreFromRecycleBin(
    RecycleItem item, {
    bool assignNewBarcodeIfConflict = false,
  }) async {
    var product = item.toProduct();
    final barcode = product.barcode;

    if (await _dao.existsBarcode(barcode)) {
      final isAuto = barcode.startsWith(AppConstants.autoBarcodePrefix);
      if (!isAuto || !assignNewBarcodeIfConflict) {
        throw StateError('条码冲突：$barcode');
      }
      product = product.copyWith(barcode: await _allocateAutoBarcode());
    }

    await _dao.insertProduct(product);
    await _recycleDao.deleteById(item.id!);
    await loadProducts();
    await refreshRecycleCount();
    return product.barcode;
  }

  Future<void> deleteRecycleItem(RecycleItem item) async {
    await _recycleDao.deleteById(item.id!);
    await refreshRecycleCount();
  }

  Future<void> clearRecycleBin() async {
    await _recycleDao.clearAll();
    await refreshRecycleCount();
  }

  Future<bool> checkBarcodeExists(String barcode) async {
    return await _dao.existsBarcode(barcode);
  }

  // ============ 按条码查商品 ============
  Future<Product?> getProductByBarcode(String barcode) async {
    return await _dao.getProductByBarcode(barcode);
  }

  // ============ 智能推荐分类 ============
  static String recommendCategory(String name) {
    final n = name;
    if (RegExp(r'烟|中华|芙蓉王|利群|黄鹤楼|玉溪').hasMatch(n)) return '烟';
    if (RegExp(r'酒|白酒|啤酒|红酒|茅台|五粮液|洋河').hasMatch(n)) return '酒';
    if (RegExp(r'水|饮料|茶|可乐|雪碧|农夫山泉|怡宝|脉动').hasMatch(n)) return '饮料';
    if (RegExp(r'零食|薯片|饼干|巧克力|辣条|瓜子|糖果').hasMatch(n)) return '零食';
    if (RegExp(r'纸巾|洗发水|牙膏|沐浴露|洗衣液').hasMatch(n)) return '日用品';
    return '未分类';
  }

  // ============ 搜索/分类/排序 ============
  void setSearchKeyword(String keyword) {
    _searchKeyword = keyword;
    _applyFilter();
    notifyListeners();
  }

  void setCategory(String category) {
    _selectedCategory = category;
    _applyFilter();
    notifyListeners();
  }

  void _applyFilter() {
    final sw = Stopwatch()..start();
    var list = _allProducts;

    // 1. 分类过滤
    if (_selectedCategory == '未分类') {
      list = list.where((p) => p.category.isEmpty).toList();
    } else if (_selectedCategory == '手动录入') {
      list = list.where((p) => p.barcode.startsWith(AppConstants.autoBarcodePrefix)).toList();
    } else if (_selectedCategory != '全部') {
      list = list.where((p) => p.category == _selectedCategory).toList();
    }

    // 2. 关键词过滤
    final kw = _searchKeyword.trim().toLowerCase();
    // 纯数字且 ≥4 位 → 视为"条码式"输入（命中条码的置顶并打标签）
    final isBarcodeLike = kw.length >= 4 && int.tryParse(kw) != null;
    if (kw.isNotEmpty) {
      list = list
          .where(
            (p) =>
                p.name.toLowerCase().contains(kw) ||
                p.barcode.toLowerCase().contains(kw) ||
                (p.brand ?? '').toLowerCase().contains(kw) ||
                (p.spec ?? '').toLowerCase().contains(kw),
          )
          .toList();
    }

    // 3. 排序
    switch (_sortMode) {
      case 'update_time_asc':
        list.sort((a, b) => a.updateTime.compareTo(b.updateTime));
        break;
      case 'price_desc':
        list.sort((a, b) {
          final c = b.sellingPrice.compareTo(a.sellingPrice);
          return c != 0 ? c : b.updateTime.compareTo(a.updateTime);
        });
        break;
      case 'price_asc':
        list.sort((a, b) {
          final c = a.sellingPrice.compareTo(b.sellingPrice);
          return c != 0 ? c : b.updateTime.compareTo(a.updateTime);
        });
        break;
      case 'name_asc':
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case 'name_desc':
        list.sort(
          (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
        );
        break;
      case 'update_time_desc':
      default:
        list.sort((a, b) => b.updateTime.compareTo(a.updateTime));
    }

    // 4. 搜索命中置顶：完全匹配 > 条码命中 > 其他
    //    List.sort 不稳定，所以用分组拼接（保持各组内的当前排序）
    if (kw.isNotEmpty) {
      final exact = <Product>[];
      final codeHit = <Product>[];
      final rest = <Product>[];
      for (final p in list) {
        final nameEq = p.name.toLowerCase() == kw;
        final codeEq = p.barcode.toLowerCase() == kw;
        if (nameEq || codeEq) {
          exact.add(p);
        } else if (isBarcodeLike && p.barcode.toLowerCase().contains(kw)) {
          codeHit.add(p);
        } else {
          rest.add(p);
        }
      }
      list = [...exact, ...codeHit, ...rest];
    }

    _filteredProducts = list;
    sw.stop();

    // 只报告超过一帧（16ms）的异常耗时，避免刷屏
    if (AppConstants.kApiDebug && sw.elapsedMilliseconds >= 16) {
      debugPrint(
        '[性能] 筛选 ${list.length} 条耗时 ${sw.elapsedMilliseconds}ms',
      );
    }
  }
}
