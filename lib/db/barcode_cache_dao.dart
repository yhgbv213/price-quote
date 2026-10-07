// lib/db/barcode_cache_dao.dart
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';
import '../utils/constants.dart';

class CacheStats {
  final int totalCount;
  final int stockCount;
  final int otherCount;
  final int totalBytes;

  CacheStats({
    required this.totalCount,
    required this.stockCount,
    required this.otherCount,
    required this.totalBytes,
  });
}

class BarcodeCacheDao {
  final DatabaseHelper _helper = DatabaseHelper();

  static const int _defaultMaxCount = AppConstants.cacheMaxCount;
  static const int _defaultMaxAgeDays = AppConstants.cacheExpireDays;

  // ============ 读 ============
  Future<String?> get(String barcode) async {
    final db = await _helper.database;
    final maps = await db.query(
      'barcode_cache',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return maps.first['api_response'] as String?;
  }

  /// 含源名与时间
  Future<Map<String, dynamic>?> getEntry(String barcode) async {
    final db = await _helper.database;
    final maps = await db.query(
      'barcode_cache',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return {
      'api_response': maps.first['api_response'] as String?,
      'cached_at': maps.first['cached_at'] as int?,
      'source_name': maps.first['source_name'] as String?,
    };
  }

  // ============ 写（记录源名）============
  Future<void> put(
    String barcode,
    String apiResponse, {
    String? sourceName,
  }) async {
    final db = await _helper.database;

    await db.delete(
      'barcode_cache',
      where: 'barcode = ?',
      whereArgs: [barcode],
    );
    await db.insert('barcode_cache', {
      'barcode': barcode,
      'api_response': apiResponse,
      'cached_at': DateTime.now().millisecondsSinceEpoch,
      'source_name': sourceName,
    });

    final maxCount = await _readMaxCount();
    await _enforceLimitInternal(db, maxCount);
  }

  // ============ 统计 ============
  Future<CacheStats> getStats() async {
    final db = await _helper.database;

    final totalR = await db.rawQuery('SELECT COUNT(*) FROM barcode_cache');
    final total = Sqflite.firstIntValue(totalR) ?? 0;

    final sizeR = await db.rawQuery(
      'SELECT SUM(LENGTH(api_response)) FROM barcode_cache',
    );
    final bytes = (sizeR.first.values.first as num?)?.toInt() ?? 0;

    final stockR = await db.rawQuery('''
      SELECT COUNT(*) FROM barcode_cache
      WHERE barcode IN (SELECT barcode FROM products)
    ''');
    final stock = Sqflite.firstIntValue(stockR) ?? 0;

    return CacheStats(
      totalCount: total,
      stockCount: stock,
      otherCount: total - stock,
      totalBytes: bytes,
    );
  }

  // ============ 上限调整 ============
  Future<int> enforceLimit(int maxCount) async {
    final db = await _helper.database;
    return await _enforceLimitInternal(db, maxCount);
  }

  Future<int> _enforceLimitInternal(Database db, int maxCount) async {
    if (maxCount <= 0) return 0;

    final totalR = await db.rawQuery('SELECT COUNT(*) FROM barcode_cache');
    final total = Sqflite.firstIntValue(totalR) ?? 0;
    if (total <= maxCount) return 0;

    final needDelete = total - maxCount;
    final oldOnes = await db.query(
      'barcode_cache',
      orderBy: 'cached_at ASC',
      limit: needDelete,
    );

    int deleted = 0;
    for (final row in oldOnes) {
      await db.delete(
        'barcode_cache',
        where: 'barcode = ?',
        whereArgs: [row['barcode']],
      );
      deleted++;
    }
    return deleted;
  }

  // ============ 过期清理 ============
  Future<int> deleteExpired(int expireDays) async {
    if (expireDays <= 0) return 0;
    final cutoff = DateTime.now()
        .subtract(Duration(days: expireDays))
        .millisecondsSinceEpoch;

    final db = await _helper.database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) FROM barcode_cache WHERE cached_at < ?',
      [cutoff],
    );
    final count = Sqflite.firstIntValue(r) ?? 0;
    await db.delete(
      'barcode_cache',
      where: 'cached_at < ?',
      whereArgs: [cutoff],
    );
    return count;
  }

  Future<void> cleanExpiredOnStartup() async {
    final expireDays = await _readExpireDays();
    if (expireDays > 0) {
      await deleteExpired(expireDays);
    }
    final maxCount = await _readMaxCount();
    await enforceLimit(maxCount);
  }

  // ============ 清空 ============
  Future<int> clearAll() async {
    final db = await _helper.database;
    final r = await db.rawQuery('SELECT COUNT(*) FROM barcode_cache');
    final count = Sqflite.firstIntValue(r) ?? 0;
    await db.delete('barcode_cache');
    return count;
  }

  // ============ 导出 ============
  Future<String> exportToJson() async {
    final db = await _helper.database;
    final rows = await db.query('barcode_cache', orderBy: 'cached_at ASC');
    final list = rows
        .map(
          (m) => {
            'barcode': m['barcode'],
            'api_response': m['api_response'],
            'cached_at': m['cached_at'],
            'source_name': m['source_name'],
          },
        )
        .toList();

    final data = {
      'format_version': 1,
      'export_time': DateTime.now().millisecondsSinceEpoch,
      'caches': list,
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  // ============ 导入 ============
  Future<CacheImportResult> importCaches(List<dynamic> caches) async {
    final db = await _helper.database;

    int added = 0;
    int updated = 0;
    int skipped = 0;

    for (final item in caches) {
      if (item is! Map) continue;
      final barcode = item['barcode'] as String?;
      final apiResponse = item['api_response'] as String?;
      final cachedAt = item['cached_at'] as int?;
      final sourceName = item['source_name'] as String?;
      if (barcode == null || apiResponse == null || cachedAt == null) continue;

      final existing = await db.query(
        'barcode_cache',
        where: 'barcode = ?',
        whereArgs: [barcode],
        limit: 1,
      );

      if (existing.isEmpty) {
        await db.insert('barcode_cache', {
          'barcode': barcode,
          'api_response': apiResponse,
          'cached_at': cachedAt,
          'source_name': sourceName,
        });
        added++;
      } else {
        final localCachedAt = existing.first['cached_at'] as int? ?? 0;
        if (cachedAt > localCachedAt) {
          await db.update(
            'barcode_cache',
            {
              'api_response': apiResponse,
              'cached_at': cachedAt,
              'source_name': sourceName,
            },
            where: 'barcode = ?',
            whereArgs: [barcode],
          );
          updated++;
        } else {
          skipped++;
        }
      }
    }

    final maxCount = await _readMaxCount();
    await _enforceLimitInternal(db, maxCount);

    return CacheImportResult(added: added, updated: updated, skipped: skipped);
  }

  // ============ 私有 ============
  Future<int> _readMaxCount() async {
    final r = await _readSetting('cache_max_count');
    return int.tryParse(r ?? '') ?? _defaultMaxCount;
  }

  Future<int> _readExpireDays() async {
    final r = await _readSetting('cache_expire_days');
    return int.tryParse(r ?? '') ?? _defaultMaxAgeDays;
  }

  Future<String?> _readSetting(String key) async {
    final db = await _helper.database;
    final maps = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return maps.first['value'] as String?;
  }
}

class CacheImportResult {
  final int added;
  final int updated;
  final int skipped;

  CacheImportResult({
    required this.added,
    required this.updated,
    required this.skipped,
  });
}
