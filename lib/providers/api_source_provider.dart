// lib/providers/api_source_provider.dart
import 'package:flutter/foundation.dart';

import '../db/api_source_dao.dart';
import '../models/api_source.dart';

class ApiSourceProvider extends ChangeNotifier {
  final ApiSourceDao _dao = ApiSourceDao();

  List<ApiSource> _sources = [];
  bool _loading = false;

  List<ApiSource> get sources => _sources;
  bool get loading => _loading;

  /// 预设模板
  static const Map<String, List<String>> presets = {
    '免费模式': ['Open Food Facts'],
    '标准模式': ['阿里云条形码API', 'Open Food Facts'],
    '离线模式': [],
    // 自定义模式不需要在这里枚举，UI 层动态生成
  };

  // ============ 加载 ============
  Future<void> loadAll() async {
    _loading = true;
    notifyListeners();
    _sources = await _dao.getAllSources();
    _loading = false;
    notifyListeners();
  }

  // ============ 启用/禁用 ============
  Future<void> toggleEnabled(ApiSource source) async {
    await _dao.setEnabled(source.id!, !source.enabled);
    await loadAll();
  }

  // ============ 删除 ============
  /// 返回 null = 成功；非空字符串 = 失败原因
  Future<String?> deleteSource(ApiSource source) async {
    final err = await _dao.canDelete(source);
    if (err != null) return err;
    await _dao.delete(source.id!);
    await loadAll();
    return null;
  }

  // ============ 新增 ============
  Future<int> addSource({
    required String name,
    required String baseUrl,
    String method = 'GET',
    String? headers,
    String? paramsTemplate,
    String? bodyTemplate,
    String? responsePath,
    int timeoutSeconds = 3,
  }) async {
    final maxPriority = await _dao.getMaxPriority();
    final source = ApiSource(
      name: name,
      baseUrl: baseUrl,
      method: method,
      headers: headers,
      paramsTemplate: paramsTemplate,
      bodyTemplate: bodyTemplate,
      responsePath: responsePath,
      isBuiltin: false,
      isProtected: false,
      enabled: false, // 默认禁用
      priority: maxPriority + 1,
      timeoutSeconds: timeoutSeconds,
    );
    final id = await _dao.insert(source);
    await loadAll();
    return id;
  }

  // ============ 更新 ============
  Future<void> updateSource(ApiSource source) async {
    await _dao.update(source);
    await loadAll();
  }

  // ============ 应用预设模板 ============
  /// 返回 true = 成功；false = 阿里云源已被删除需重新添加
  Future<bool> applyPreset(String presetName) async {
    final targets = presets[presetName] ?? [];
    bool needsAliYun = false;

    // 1. 先全部禁用
    for (final s in _sources) {
      if (s.enabled) {
        await _dao.setEnabled(s.id!, false);
      }
    }

    // 2. 启用目标源
    for (final name in targets) {
      final matched = _sources.where((s) => s.name == name).toList();
      if (matched.isNotEmpty) {
        await _dao.setEnabled(matched.first.id!, true);
      } else if (name == '阿里云条形码API') {
        needsAliYun = true;
      }
    }

    await loadAll();
    return !needsAliYun;
  }

  /// 重新添加阿里云模板（用户删掉后，切换标准模式时调用）
  Future<void> reAddAliYun() async {
    final maxPriority = await _dao.getMaxPriority();
    await _dao.insert(
      ApiSource(
        name: '阿里云条形码API',
        baseUrl: 'https://api.example.com/barcode?code={barcode}',
        method: 'GET',
        responsePath: 'data.name',
        isBuiltin: true,
        isProtected: false,
        enabled: false,
        priority: maxPriority + 1,
        timeoutSeconds: 3,
      ),
    );
    await loadAll();
  }

  /// 当前匹配的预设名（用于 UI 显示选中状态）
  String currentPresetName() {
    final enabledNames = _sources
        .where((s) => s.enabled)
        .map((s) => s.name)
        .toSet();
    if (enabledNames.isEmpty) return '离线模式';
    if (enabledNames.length == 1 && enabledNames.first == 'Open Food Facts') {
      return '免费模式';
    }
    if (enabledNames.length == 2 &&
        enabledNames.contains('Open Food Facts') &&
        enabledNames.contains('阿里云条形码API')) {
      return '标准模式';
    }
    return '自定义模式';
  }
}
