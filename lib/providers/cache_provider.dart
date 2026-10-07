// lib/providers/cache_provider.dart
import 'dart:io';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/barcode_cache_dao.dart';
import '../db/app_settings_dao.dart';
import '../utils/constants.dart';

class CacheProvider extends ChangeNotifier {
  final BarcodeCacheDao _dao = BarcodeCacheDao();
  final AppSettingsDao _settingsDao = AppSettingsDao();

  int _maxCount = AppConstants.cacheMaxCount;
  int _expireDays = AppConstants.cacheExpireDays;
  CacheStats? _stats;
  bool _loading = false;
  bool _cacheEnabled = true;

  int get maxCount => _maxCount;
  int get expireDays => _expireDays;
  CacheStats? get stats => _stats;
  bool get loading => _loading;
  bool get cacheEnabled => _cacheEnabled;

  // 档位常量
  static const List<int> maxCountOptions = [
    1000,
    2000,
    5000,
    10000,
    -1,
  ]; // -1 = 不限
  static const List<int> expireDaysOptions = [90, 180, -1]; // -1 = 永久

  // ============ 加载 ============
  Future<void> load() async {
    _loading = true;
    notifyListeners();

    _maxCount =
        int.tryParse(
          await _settingsDao.get('cache_max_count') ??
              '${AppConstants.cacheMaxCount}',
        ) ??
        AppConstants.cacheMaxCount;
    _expireDays =
        int.tryParse(
          await _settingsDao.get('cache_expire_days') ??
              '${AppConstants.cacheExpireDays}',
        ) ??
        AppConstants.cacheExpireDays;
    _cacheEnabled =
        (await _settingsDao.get('cache_enabled') ?? 'true') == 'true';
    _stats = await _dao.getStats();

    _loading = false;
    notifyListeners();
  }

  // ============ 缓存总开关 ============
  /// 关闭后：不读缓存、不写缓存，但**已有缓存保留**（重新开启可继续用）
  Future<void> setCacheEnabled(bool v) async {
    _cacheEnabled = v;
    await _settingsDao.set('cache_enabled', v ? 'true' : 'false');
    notifyListeners();
  }

  // ============ 调整上限 ============
  /// 返回实际淘汰条数
  Future<int> setMaxCount(int v) async {
    _maxCount = v;
    await _settingsDao.set('cache_max_count', v.toString());
    int deleted = 0;
    if (v > 0) {
      deleted = await _dao.enforceLimit(v);
    }
    await load();
    return deleted;
  }

  // ============ 调整过期时间 ============
  /// 返回实际清理条数
  Future<int> setExpireDays(int v) async {
    _expireDays = v;
    await _settingsDao.set('cache_expire_days', v.toString());
    int deleted = 0;
    if (v > 0) {
      deleted = await _dao.deleteExpired(v);
    }
    await load();
    return deleted;
  }

  // ============ 清空 ============
  Future<int> clearAll() async {
    final count = await _dao.clearAll();
    await load();
    return count;
  }

  // ============ 导出并分享 ============
  Future<void> exportAndShare() async {
    final json = await _dao.exportToJson();
    final dir = await getTemporaryDirectory();
    final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
    final fileName = 'barcode_cache_$dateStr.json';
    final file = File(path.join(dir.path, fileName));
    await file.writeAsString(json);
    try {
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'application/json'),
      ], subject: fileName);
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  // ============ 导入缓存 ============
  /// 返回导入结果，失败抛异常
  Future<CacheImportResult> importFromFile() async {
    // 1. 选文件
    final pickResult = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (pickResult == null || pickResult.files.isEmpty) {
      throw Exception('未选择文件');
    }

    final file = pickResult.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      throw Exception('无法读取文件');
    }

    // 2. 解析 JSON
    final jsonStr = utf8.decode(bytes);
    dynamic data;
    try {
      data = jsonDecode(jsonStr);
    } catch (_) {
      throw Exception('文件格式不正确，无法导入');
    }

    // 3. 校验 format_version
    if (data is! Map || data['format_version'] != 1) {
      throw Exception('文件格式版本不兼容，请更新 App');
    }
    final caches = data['caches'];
    if (caches is! List) {
      throw Exception('文件内容格式错误');
    }

    // 4. 合并（库存优先 + 时间较新覆盖）
    final result = await _dao.importCaches(caches);

    // 5. 重新加载
    await load();

    return result;
  }
}
