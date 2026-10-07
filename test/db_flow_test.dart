// test/db_flow_test.dart
//
// 数据库层集成测试：桌面用 sqflite_common_ffi 跑真实 SQLite，
// 覆盖 DAO / Provider / Service 的实际读写逻辑（无需真机）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:price_query_app/db/app_settings_dao.dart';
import 'package:price_query_app/db/database_helper.dart';
import 'package:price_query_app/db/price_history_dao.dart';
import 'package:price_query_app/db/product_dao.dart';
import 'package:price_query_app/models/product.dart';
import 'package:price_query_app/providers/product_provider.dart';
import 'package:price_query_app/providers/quote_provider.dart';
import 'package:price_query_app/services/backup_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    tempDir = await Directory.systemTemp.createTemp('pq_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
  });

  tearDownAll(() async {
    await DatabaseHelper().close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    final db = await DatabaseHelper().database;
    for (final t in [
      'products',
      'recycle_bin',
      'barcode_cache',
      'price_history',
      'quote_items',
      'quotes',
    ]) {
      await db.delete(t);
    }
    await AppSettingsDao().set('custom_categories', '[]');
  });

  // ==================== 数据层基础 ====================

  test('数据库建表并可写入/读取商品', () async {
    final dao = ProductDao();
    final id = await dao.insertProduct(
      Product(
        barcode: '6901234567890',
        name: '测试商品',
        category: '零食',
        sellingPrice: 9.9,
        updateTime: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    expect(id, greaterThan(0));

    final p = await dao.getProductByBarcode('6901234567890');
    expect(p, isNotNull);
    expect(p!.name, '测试商品');
    expect(p.sellingPrice, 9.9);
    expect(p.category, '零食');
  });

  test('价格历史每商品最多保留 20 条', () async {
    final dao = PriceHistoryDao();
    for (var i = 1; i <= 25; i++) {
      await dao.insert(barcode: 'H1', price: i.toDouble());
    }
    final db = await DatabaseHelper().database;
    final rows = await db.query('price_history', where: 'barcode = ?', whereArgs: ['H1']);
    expect(rows.length, 20);
    // 保留的应该是最新的 20 条（最大价格 25 在内）
    final latest = await dao.getLatestPrice('H1');
    expect(latest, 25.0);
  });

  // ==================== 备份导出 / 导入 ====================

  test('备份导出 → 导入往返：商品、价格历史、分类都能恢复', () async {
    final productDao = ProductDao();
    final historyDao = PriceHistoryDao();
    final settingsDao = AppSettingsDao();
    final service = BackupService();

    await productDao.insertProduct(
      Product(
        barcode: '6900000000001',
        name: '可乐',
        category: '饮料',
        sellingPrice: 3.5,
        updateTime: 1000,
      ),
    );
    await productDao.insertProduct(
      Product(
        barcode: 'AUTO_1',
        name: '手动录入品',
        category: '其他',
        sellingPrice: 12.0,
        updateTime: 2000,
      ),
    );
    await historyDao.insert(barcode: '6900000000001', price: 3.5);
    await settingsDao.set('custom_categories', jsonEncode(['烟', '酒']));

    // --- 导出 ---
    final file = await service.generateBackupFile();
    expect(await file.exists(), isTrue);
    final text = await file.readAsString();

    final decoded = jsonDecode(text) as Map<String, dynamic>;
    expect(decoded['format_version'], 1);
    expect((decoded['products'] as List).length, 2);
    expect((decoded['price_history'] as List).length, 1);
    expect(decoded['custom_categories'], containsAll(['烟', '酒']));

    // --- 清空后导入，应全部为"新增" ---
    final db = await DatabaseHelper().database;
    await db.delete('products');
    await db.delete('price_history');
    await settingsDao.set('custom_categories', '[]');

    final preview = await service.previewImport(text);
    expect(preview.total, 2);
    expect(preview.added, 2);
    expect(preview.updated, 0);
    expect(preview.skipped, 0);

    final result = await service.applyImport(preview);
    expect(result.added, 2);
    expect(result.updated, 0);

    final restored = await productDao.getProductByBarcode('6900000000001');
    expect(restored, isNotNull);
    expect(restored!.name, '可乐');
    expect(restored.sellingPrice, 3.5);
    expect(restored.category, '饮料');
    expect(restored.imageSource, 'none'); // 备份不含图片

    // AUTO_ 条码原样保留
    expect(await productDao.getProductByBarcode('AUTO_1'), isNotNull);

    // 价格历史恢复
    expect(await historyDao.getLatestPrice('6900000000001'), 3.5);

    // 分类与本地取并集
    final cats =
        jsonDecode(await settingsDao.get('custom_categories') ?? '[]') as List;
    expect(cats, containsAll(['烟', '酒']));
  });

  test('导入合并规则：同条码较新覆盖 / 本地较新跳过 / 新条码追加', () async {
    final dao = ProductDao();
    final service = BackupService();

    await dao.insertProduct(
      Product(barcode: 'B1', name: '本地版', sellingPrice: 1.0, updateTime: 5000),
    );
    await dao.insertProduct(
      Product(barcode: 'B2', name: '本地版2', sellingPrice: 2.0, updateTime: 5000),
    );

    final backup = jsonEncode({
      'format_version': 1,
      'products': [
        {'barcode': 'B1', 'name': '备份版', 'category': '', 'selling_price': 11.0, 'update_time': 9000},
        {'barcode': 'B2', 'name': '备份版2', 'category': '', 'selling_price': 22.0, 'update_time': 1000},
        {'barcode': 'B3', 'name': '备份版3', 'category': '', 'selling_price': 33.0, 'update_time': 9000},
      ],
      'price_history': <Map<String, dynamic>>[],
      'custom_categories': <String>[],
    });

    final preview = await service.previewImport(backup);
    expect(preview.added, 1);
    expect(preview.updated, 1);
    expect(preview.skipped, 1);

    final result = await service.applyImport(preview);
    expect(result.added, 1);
    expect(result.updated, 1);
    expect(result.skipped, 1);

    // B1：备份较新 → 被覆盖
    final b1 = await dao.getProductByBarcode('B1');
    expect(b1!.name, '备份版');
    expect(b1.sellingPrice, 11.0);

    // B2：本地较新 → 保持原样
    final b2 = await dao.getProductByBarcode('B2');
    expect(b2!.name, '本地版2');
    expect(b2.sellingPrice, 2.0);

    // B3：追加
    expect(await dao.getProductByBarcode('B3'), isNotNull);
  });

  test('导入更新已有商品时保留本地图片（防同机导入丢图）', () async {
    final dao = ProductDao();
    await dao.insertProduct(
      Product(
        barcode: 'IMG1',
        name: '有图商品',
        sellingPrice: 1.0,
        updateTime: 1000,
        localImagePath: 'images/IMG1.jpg',
        imageSource: 'manual',
      ),
    );

    final service = BackupService();
    final backup = jsonEncode({
      'format_version': 1,
      'products': [
        {'barcode': 'IMG1', 'name': '新版名称', 'category': '', 'selling_price': 2.0, 'update_time': 9999},
      ],
      'price_history': <Map<String, dynamic>>[],
      'custom_categories': <String>[],
    });

    final preview = await service.previewImport(backup);
    await service.applyImport(preview);

    final p = await dao.getProductByBarcode('IMG1');
    expect(p!.name, '新版名称');
    expect(p.localImagePath, 'images/IMG1.jpg'); // 图片路径保留
    expect(p.imageSource, 'manual');
  });

  test('导入校验：非 JSON / 缺版本号 / 版本过高 都要报错', () async {
    final service = BackupService();
    expect(
      () => service.previewImport('这不是 JSON'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => service.previewImport(jsonEncode({'products': []})),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => service.previewImport(
        jsonEncode({'format_version': 99, 'products': []}),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('导入时过滤缺条码/名称的脏数据', () async {
    final service = BackupService();
    final backup = jsonEncode({
      'format_version': 1,
      'products': [
        {'barcode': '', 'name': '无条码', 'selling_price': 1.0, 'update_time': 1},
        {'barcode': 'OK1', 'name': '', 'selling_price': 1.0, 'update_time': 1},
        {'barcode': 'OK2', 'name': '正常商品', 'selling_price': 1.0, 'update_time': 1},
      ],
      'price_history': <Map<String, dynamic>>[],
      'custom_categories': <String>[],
    });

    final preview = await service.previewImport(backup);
    expect(preview.total, 1);
    expect(preview.products.first['barcode'], 'OK2');
  });

  // ==================== 报价单 ====================

  test('报价单：同商品累加数量，总价与件数正确，单价为快照', () async {
    final provider = QuoteProvider();
    await provider.loadOrCreateDraft();
    expect(provider.isEmpty, isTrue);

    final p = Product(
      barcode: 'QP1',
      name: '报价商品',
      spec: '500ml',
      sellingPrice: 5.0,
      updateTime: 1,
    );
    await provider.addProduct(p);
    await provider.addProduct(p); // 同一商品 → 数量 +1

    expect(provider.lineCount, 1);
    expect(provider.itemCount, 2); // SUM(quantity) = 2
    expect(provider.totalPrice, 10.0);
    expect(provider.items.first.unitPrice, 5.0);
    expect(provider.items.first.subtotal, 10.0);

    // 数量调整
    provider.increment(0);
    expect(provider.itemCount, 3);
    expect(provider.totalPrice, 15.0);

    provider.decrement(0);
    expect(provider.itemCount, 2);

    // 保存转正后内存清空
    final err = await provider.saveAsOfficial();
    expect(err, isNull);
    expect(provider.isEmpty, isTrue);
    expect(provider.itemCount, 0);
  });

  test('报价单：空单保存被拦截', () async {
    final provider = QuoteProvider();
    await provider.loadOrCreateDraft();
    final err = await provider.saveAsOfficial();
    expect(err, '报价单为空，无法保存');
    await provider.flushNow();
  });

  // ==================== 搜索过滤与置顶 ====================

  test('搜索：四字段匹配、完全匹配与条码命中置顶', () async {
    final dao = ProductDao();
    await dao.insertProduct(
      Product(barcode: '6901111111111', name: '农夫山泉', brand: '农夫', sellingPrice: 2.0, updateTime: 1),
    );
    await dao.insertProduct(
      Product(barcode: '6902222222222', name: '含6901111111111字样的名称', sellingPrice: 3.0, updateTime: 2),
    );
    await dao.insertProduct(
      Product(barcode: 'X1', name: '可口可乐', spec: '330ml', sellingPrice: 4.0, updateTime: 3),
    );

    final provider = ProductProvider();
    await provider.loadProducts();
    expect(provider.products.length, 3);

    // 名称匹配
    provider.setSearchKeyword('可乐');
    expect(provider.products.length, 1);
    expect(provider.products.first.name, '可口可乐');

    // 规格匹配
    provider.setSearchKeyword('330');
    expect(provider.products.length, 1);

    // 纯数字长条码 → 置顶为精确条码命中的那条
    provider.setSearchKeyword('6901111111111');
    expect(provider.isBarcodeSearch, isTrue);
    expect(provider.products.length, 2);
    expect(provider.products.first.barcode, '6901111111111');

    // "AUTO" 关键词能查到手动录入商品
    await dao.insertProduct(
      Product(barcode: 'AUTO_9', name: '手动品', sellingPrice: 1.0, updateTime: 9),
    );
    await provider.loadProducts();
    provider.setSearchKeyword('AUTO');
    expect(provider.isBarcodeSearch, isFalse);
    expect(provider.products.length, 1);
    expect(provider.products.first.barcode, 'AUTO_9');
  });

  test('分类筛选与"手动录入"芯片', () async {
    final dao = ProductDao();
    await dao.insertProduct(
      Product(barcode: 'C1', name: '烟品', category: '烟', sellingPrice: 1.0, updateTime: 1),
    );
    await dao.insertProduct(
      Product(barcode: 'AUTO_1', name: '手动品', category: '', sellingPrice: 1.0, updateTime: 2),
    );

    final provider = ProductProvider();
    await provider.loadProducts();

    provider.setCategory('烟');
    expect(provider.products.length, 1);

    provider.setCategory('未分类');
    expect(provider.products.length, 1);
    expect(provider.products.first.barcode, 'AUTO_1');

    provider.setCategory('手动录入');
    expect(provider.products.length, 1);
    expect(provider.products.first.barcode, 'AUTO_1');

    provider.setCategory('全部');
    expect(provider.products.length, 2);
  });

  // ==================== AUTO_N 分配 ====================

  test('AUTO_N 分配：扫描最小空洞', () async {
    final provider = ProductProvider();
    await provider.loadProducts();

    expect(
      await provider.saveNewProduct(barcode: '', name: 'A', category: '', sellingPrice: 1),
      'AUTO_1',
    );
    expect(
      await provider.saveNewProduct(barcode: '', name: 'B', category: '', sellingPrice: 1),
      'AUTO_2',
    );
    expect(
      await provider.saveNewProduct(barcode: '', name: 'C', category: '', sellingPrice: 1),
      'AUTO_3',
    );

    // 物理删除 AUTO_2 → 下次应复用这个"空洞"
    final p2 = await provider.getProductByBarcode('AUTO_2');
    await ProductDao().deleteProductById(p2!.id!);
    await provider.loadProducts();

    expect(
      await provider.saveNewProduct(barcode: '', name: 'D', category: '', sellingPrice: 1),
      'AUTO_2',
    );
  });

  // ==================== 已知未实现（1.1 范围） ====================

  test('回收站恢复：AUTO_N 被重新占用时不应崩溃（文档 6.4 场景 C）', () async {
    final provider = ProductProvider();
    await provider.loadProducts();
    await provider.saveNewProduct(
      barcode: '',
      name: 'A',
      category: '',
      sellingPrice: 1,
    );

    final p = await provider.getProductByBarcode('AUTO_1');
    await provider.moveToRecycleBin(p!);

    // 主表已空 → 新商品再次拿到 AUTO_1（与回收站里的那条重号）
    final reused = await provider.saveNewProduct(
      barcode: '',
      name: 'B',
      category: '',
      sellingPrice: 1,
    );
    expect(reused, 'AUTO_1');

    // 此时从回收站恢复那条 AUTO_1
    final items = await provider.loadRecycleItems();
    expect(items.length, 1);

    // 未授权换号 → 必须抛可识别异常，而不是让 SQL 层 UNIQUE 崩溃
    await expectLater(
      provider.restoreFromRecycleBin(items.first),
      throwsA(isA<StateError>()),
    );

    // 授权换号（界面向用户确认后）→ 恢复成功且新序号不与现有冲突
    final newBarcode = await provider.restoreFromRecycleBin(
      items.first,
      assignNewBarcodeIfConflict: true,
    );
    expect(newBarcode, isNot('AUTO_1'));

    final all = await ProductDao().getAllProducts();
    expect(all.length, 2);
    expect(all.map((e) => e.barcode).toSet().length, 2);
  });

  test(
    '序号锁定：回收站中的 AUTO_N 应阻止重复分配',
    () async {
      final provider = ProductProvider();
      await provider.loadProducts();
      await provider.saveNewProduct(barcode: '', name: 'A', category: '', sellingPrice: 1);

      final p = await provider.getProductByBarcode('AUTO_1');
      await provider.moveToRecycleBin(p!);

      // 文档 5.1：回收站存在即锁定 → 应分配 AUTO_2
      final next =
          await provider.saveNewProduct(barcode: '', name: 'B', category: '', sellingPrice: 1);
      expect(next, 'AUTO_2');
    },
    skip: '序号锁定/回收属 1.1 范围（文档 5.1 / 6.4），当前 _allocateAutoBarcode 只扫主表',
  );
}
