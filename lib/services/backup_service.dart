// lib/services/backup_service.dart
import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import '../db/product_dao.dart';
import '../db/app_settings_dao.dart';
import '../utils/constants.dart';

class BackupService {
  static const int formatVersion = 1;

  final ProductDao _productDao = ProductDao();
  final AppSettingsDao _settingsDao = AppSettingsDao();

  /// 导出商品数据为 JSON，返回生成的文件路径（调用方自行决定后续处理）
  Future<File> generateBackupFile() async {
    // 1. 收集数据
    final products = await _productDao.getAllProducts();
    final customCategoriesJson =
        await _settingsDao.get('custom_categories') ?? '[]';

    // 2. 价格历史
    final db = await DatabaseHelper().database;
    final historyMaps = await db.query('price_history');
    final priceHistory = historyMaps
        .map(
          (m) => {
            'barcode': m['barcode'],
            'price': m['price'],
            'record_time': m['record_time'],
          },
        )
        .toList();

    // 3. 组装 JSON
    final data = {
      'format_version': formatVersion,
      'export_time': DateTime.now().millisecondsSinceEpoch,
      'products': products.map((p) => p.toMap()).toList(),
      'price_history': priceHistory,
      'custom_categories': jsonDecode(customCategoriesJson),
    };

    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);

    // 4. 写入临时文件
    final dir = await getTemporaryDirectory();
    final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
    final fileName = 'products_backup_$dateStr.json';
    final file = File(path.join(dir.path, fileName));
    await file.writeAsString(jsonStr);

    return file;
  }

  /// 导出 + 调起分享
  Future<void> exportAndShare() async {
    final file = await generateBackupFile();
    try {
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'application/json'),
      ], subject: path.basename(file.path));
    } finally {
      // 分享面板关闭后删除临时文件
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

  // ==================== 导入（V6.0.1） ====================

  /// 解析备份文件文本，生成导入预览（只读，不写库）
  Future<BackupImportPreview> previewImport(String jsonText) async {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map) {
      throw const FormatException('不是有效的备份文件');
    }
    final map = Map<String, dynamic>.from(decoded);

    final version = map['format_version'];
    if (version is! int) {
      throw const FormatException('文件缺少 format_version 字段');
    }
    if (version > formatVersion) {
      throw FormatException(
        '文件版本不兼容（format_version=$version，当前支持 ≤$formatVersion）',
      );
    }

    // 商品：过滤缺条码/名称的脏数据
    final products = <Map<String, dynamic>>[];
    for (final raw in (map['products'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final barcode = (m['barcode'] as String?)?.trim() ?? '';
      final name = (m['name'] as String?)?.trim() ?? '';
      if (barcode.isEmpty || name.isEmpty) continue;
      products.add(m);
    }

    // 价格历史
    final history = <Map<String, dynamic>>[];
    for (final raw in (map['price_history'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final bc = (m['barcode'] as String?)?.trim() ?? '';
      if (bc.isEmpty) continue;
      history.add(m);
    }

    // 分类设置
    final categories = <String>[];
    for (final raw in (map['custom_categories'] as List? ?? const [])) {
      if (raw is String && raw.trim().isNotEmpty) categories.add(raw.trim());
    }

    // 与本地比对（同条码：文件较新 → 更新，本地较新 → 跳过）
    final db = await DatabaseHelper().database;
    final localRows = await db.query(
      'products',
      columns: ['barcode', 'update_time'],
    );
    final localUpdateTime = <String, int>{
      for (final r in localRows)
        r['barcode'] as String: (r['update_time'] as num?)?.toInt() ?? 0,
    };

    var added = 0, updated = 0, skipped = 0;
    for (final p in products) {
      final barcode = p['barcode'] as String;
      final incoming = (p['update_time'] as num?)?.toInt() ?? 0;
      final local = localUpdateTime[barcode];
      if (local == null) {
        added++;
      } else if (incoming > local) {
        updated++;
      } else {
        skipped++;
      }
    }

    return BackupImportPreview(
      products: products,
      priceHistory: history,
      customCategories: categories,
      total: products.length,
      added: added,
      updated: updated,
      skipped: skipped,
    );
  }

  /// 执行导入（单事务）。
  ///
  /// 合并规则：同条码按 update_time 较新覆盖，不同条码追加。
  /// 图片不随备份文件走：新增商品无图片；更新商品保留本地已有图片。
  Future<BackupImportResult> applyImport(BackupImportPreview preview) async {
    final db = await DatabaseHelper().database;

    var added = 0, updated = 0, skipped = 0, historyWritten = 0;
    final touchedBarcodes = <String>[];

    await db.transaction((txn) async {
      final localRows = await txn.query(
        'products',
        columns: ['barcode', 'update_time', 'local_image_path', 'image_source'],
      );
      final localMap = <String, Map<String, dynamic>>{
        for (final r in localRows) r['barcode'] as String: r,
      };

      for (final p in preview.products) {
        final barcode = p['barcode'] as String;
        final incoming = (p['update_time'] as num?)?.toInt() ?? 0;
        final local = localMap[barcode];

        final row = <String, dynamic>{
          'barcode': barcode,
          'name': (p['name'] as String).trim(),
          'brand': p['brand'],
          'spec': p['spec'],
          'category': p['category'] ?? '',
          'selling_price': (p['selling_price'] as num?)?.toDouble() ?? 0,
          'update_time': incoming,
        };

        if (local == null) {
          row['local_image_path'] = null;
          row['image_source'] = 'none';
          await txn.insert('products', row);
          added++;
          touchedBarcodes.add(barcode);
        } else if (incoming > ((local['update_time'] as num?)?.toInt() ?? 0)) {
          // 保留本地已有图片路径，避免同机导入时丢图
          final localPath = local['local_image_path'] as String?;
          row['local_image_path'] = localPath;
          row['image_source'] = (localPath == null || localPath.isEmpty)
              ? 'none'
              : (local['image_source'] ?? 'manual');
          await txn.update(
            'products',
            row,
            where: 'barcode = ?',
            whereArgs: [barcode],
          );
          updated++;
          touchedBarcodes.add(barcode);
        } else {
          skipped++;
        }
      }

      // 价格历史：只覆盖本次新增/更新商品的历史，避免重复累积
      if (touchedBarcodes.isNotEmpty && preview.priceHistory.isNotEmpty) {
        final touched = touchedBarcodes.toSet();
        final byBarcode = <String, List<Map<String, dynamic>>>{};
        for (final h in preview.priceHistory) {
          final bc = h['barcode'] as String;
          if (!touched.contains(bc)) continue;
          byBarcode.putIfAbsent(bc, () => []).add(h);
        }

        for (final entry in byBarcode.entries) {
          await txn.delete(
            'price_history',
            where: 'barcode = ?',
            whereArgs: [entry.key],
          );
          final list = entry.value.toList()
            ..sort(
              (a, b) => ((b['record_time'] as num?)?.toInt() ?? 0).compareTo(
                (a['record_time'] as num?)?.toInt() ?? 0,
              ),
            );
          for (final h in list.take(
            AppConstants.priceHistoryMaxPerProduct,
          )) {
            await txn.insert('price_history', {
              'barcode': entry.key,
              'price': (h['price'] as num?)?.toDouble() ?? 0,
              'record_time': (h['record_time'] as num?)?.toInt() ?? 0,
            });
            historyWritten++;
          }
        }
      }

      // 分类设置：与本地取并集
      if (preview.customCategories.isNotEmpty) {
        final rows = await txn.query(
          'app_settings',
          where: 'key = ?',
          whereArgs: ['custom_categories'],
          limit: 1,
        );
        final merged = <String>{};
        if (rows.isNotEmpty) {
          try {
            for (final c in (jsonDecode(rows.first['value'] as String) as List)) {
              if (c is String) merged.add(c);
            }
          } catch (_) {
            // 旧数据损坏时忽略，直接用文件里的分类
          }
        }
        merged.addAll(preview.customCategories);
        await txn.insert('app_settings', {
          'key': 'custom_categories',
          'value': jsonEncode(merged.toList()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });

    return BackupImportResult(
      added: added,
      updated: updated,
      skipped: skipped,
      historyWritten: historyWritten,
    );
  }
}

/// 导入预览（解析 + 与本地比对的结果，尚未写库）
class BackupImportPreview {
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> priceHistory;
  final List<String> customCategories;
  final int total;
  final int added;
  final int updated;
  final int skipped;

  const BackupImportPreview({
    required this.products,
    required this.priceHistory,
    required this.customCategories,
    required this.total,
    required this.added,
    required this.updated,
    required this.skipped,
  });
}

/// 导入结果统计
class BackupImportResult {
  final int added;
  final int updated;
  final int skipped;
  final int historyWritten;

  const BackupImportResult({
    required this.added,
    required this.updated,
    required this.skipped,
    required this.historyWritten,
  });

  int get total => added + updated + skipped;
}
