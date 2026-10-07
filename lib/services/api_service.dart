// lib/services/api_service.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../db/api_source_dao.dart';
import '../db/barcode_cache_dao.dart';
import '../db/app_settings_dao.dart';
import '../models/api_source.dart';
import '../models/api_result.dart';
import '../utils/constants.dart';

class ApiService {
  final ApiSourceDao _sourceDao = ApiSourceDao();
  final BarcodeCacheDao _cacheDao = BarcodeCacheDao();
  final AppSettingsDao _settingsDao = AppSettingsDao();

  /// 主入口
  /// [forceRefresh] = true 时跳过缓存，直接请求网络
  Future<ApiResult> query(String barcode, {bool forceRefresh = false}) async {
    if (barcode.trim().isEmpty) {
      return ApiResult.fail('条码为空');
    }
    final code = barcode.trim();
    final cacheEnabled = await _isCacheEnabled();

    // 1. 缓存优先（forceRefresh 时跳过）
    if (cacheEnabled && !forceRefresh) {
      final entry = await _cacheDao.getEntry(code);
      if (entry != null) {
        final raw = entry['api_response'] as String?;
        final cachedAt = entry['cached_at'] as int?;
        final cachedSourceName = entry['source_name'] as String?;
        if (raw != null) {
          _log('[API] 命中缓存: $code (源: ${cachedSourceName ?? "未知"})');

          // 按源名找对应源
          final allSources = await _sourceDao.getAllSources();
          ApiSource? matchingSource;
          if (cachedSourceName != null && cachedSourceName.isNotEmpty) {
            for (final s in allSources) {
              if (s.name == cachedSourceName) {
                matchingSource = s;
                break;
              }
            }
          }

          // 决定用哪条路径解析
          String? pathToUse;
          String displaySource;
          if (matchingSource != null) {
            pathToUse = matchingSource.responsePath;
            displaySource = cachedSourceName!;
          } else {
            // 源被删了 → 用当前第一启用源兜底
            final enabledSources = await _sourceDao.getEnabledSources();
            if (enabledSources.isNotEmpty) {
              pathToUse = enabledSources.first.responsePath;
            }
            displaySource = '缓存（源已删除）';
          }

          final result = _parseRaw(raw, displaySource, pathToUse);
          if (result.success) {
            final ageMs = cachedAt != null
                ? DateTime.now().millisecondsSinceEpoch - cachedAt
                : null;
            return ApiResult(
              success: true,
              name: result.name,
              brand: result.brand,
              spec: result.spec,
              imageUrl: result.imageUrl,
              price: result.price,
              rawResponse: raw,
              sourceName: displaySource,
              isFromCache: true,
              elapsedMs: 0,
              cacheAgeMs: ageMs,
            );
          }
          _log('[API] 缓存解析失败，继续走网络');
        }
      }
    }

    // 2. 按优先级请求网络
    final sources = await _sourceDao.getEnabledSources();
    if (sources.isEmpty) {
      return ApiResult.fail('未启用任何数据源');
    }

    String? lastError;
    for (final source in sources) {
      try {
        _log('[API] 尝试源: ${source.name} (优先级${source.priority})');
        final startMs = DateTime.now().millisecondsSinceEpoch;
        final raw = await _requestSource(source, code);
        final elapsedMs = DateTime.now().millisecondsSinceEpoch - startMs;

        if (raw == null || raw.isEmpty) {
          lastError = '${source.name}: 无返回';
          continue;
        }
        final result = _parseRaw(raw, source.name, source.responsePath);
        if (result.success && (result.name?.isNotEmpty ?? false)) {
          // 缓存启用时写入（记源名）
          if (cacheEnabled) {
            await _cacheDao.put(code, raw, sourceName: source.name);
          }
          _log('[API] 成功: ${result.name} (${source.name})');
          return ApiResult(
            success: true,
            name: result.name,
            brand: result.brand,
            spec: result.spec,
            imageUrl: result.imageUrl,
            price: result.price,
            rawResponse: raw,
            sourceName: source.name,
            isFromCache: false,
            elapsedMs: elapsedMs,
          );
        } else {
          lastError = '${source.name}: ${result.errorMessage ?? "解析后无名称"}';
        }
      } catch (e) {
        lastError = '${source.name}: $e';
        _log('[API] 失败: $e');
      }
    }

    return ApiResult.fail(
      '所有数据源均无结果${lastError != null ? " ($lastError)" : ""}',
    );
  }

  // ============ 缓存开关 ============
  Future<bool> _isCacheEnabled() async {
    final v = await _settingsDao.get('cache_enabled') ?? 'true';
    return v == 'true';
  }

  // ============ 请求 ============
  Future<String?> _requestSource(ApiSource source, String barcode) async {
    final url = source.baseUrl.replaceAll('{barcode}', barcode);
    final uri = Uri.parse(url);
    final timeout = Duration(seconds: source.timeoutSeconds);

    http.Response resp;
    if (source.method.toUpperCase() == 'POST') {
      final body = (source.bodyTemplate ?? '').replaceAll('{barcode}', barcode);
      resp = await http
          .post(uri, headers: _parseHeaders(source.headers), body: body)
          .timeout(timeout);
    } else {
      resp = await http
          .get(uri, headers: _parseHeaders(source.headers))
          .timeout(timeout);
    }

    if (resp.statusCode != 200) return null;
    return resp.body;
  }

  Map<String, String>? _parseHeaders(String? headersJson) {
    if (headersJson == null || headersJson.trim().isEmpty) return null;
    try {
      final map = jsonDecode(headersJson) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return null;
    }
  }

  // ============ 解析 ============
  ApiResult _parseRaw(String raw, String sourceName, String? responsePath) {
    dynamic json;
    try {
      json = jsonDecode(raw);
    } catch (_) {
      final text = raw.trim();
      if (text.isEmpty) return ApiResult.fail('空响应');
      return ApiResult.ok(name: text, sourceName: sourceName, rawResponse: raw);
    }

    final mappings = _parseResponsePath(responsePath);

    final name = _extractFirst(json, mappings['name'] ?? []);
    final brand = _extractFirst(json, mappings['brand'] ?? []);
    final spec = _extractFirst(json, mappings['spec'] ?? []);
    final imageUrl = _extractFirst(json, mappings['image_url'] ?? []);
    final priceStr = _extractFirst(json, mappings['price'] ?? []);
    final price = priceStr != null ? double.tryParse(priceStr) : null;

    if (name == null || name.isEmpty) {
      return ApiResult.fail('未解析到商品名称');
    }

    return ApiResult.ok(
      name: name,
      brand: brand,
      spec: spec,
      imageUrl: imageUrl,
      price: price,
      rawResponse: raw,
      sourceName: sourceName,
    );
  }

  Map<String, List<String>> _parseResponsePath(String? path) {
    if (path == null || path.trim().isEmpty) return {};
    final trimmed = path.trim();

    if (!trimmed.contains(':')) {
      final paths = trimmed
          .split('|')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      return {'name': paths};
    }

    final result = <String, List<String>>{};
    String? currentField;

    for (final rawSeg in trimmed.split('|')) {
      final seg = rawSeg.trim();
      if (seg.isEmpty) continue;

      if (seg.contains(':')) {
        final idx = seg.indexOf(':');
        final field = seg.substring(0, idx).trim();
        final p = seg.substring(idx + 1).trim();
        if (field.isEmpty || p.isEmpty) continue;
        currentField = field;
        result.putIfAbsent(field, () => []).add(p);
      } else {
        if (currentField != null) {
          result[currentField]!.add(seg);
        }
      }
    }

    return result;
  }

  String? _extractFirst(dynamic json, List<String> paths) {
    for (final p in paths) {
      final v = _getByPath(json, p);
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }
    return null;
  }

  dynamic _getByPath(dynamic json, String path) {
    if (path.isEmpty) return null;
    final parts = path.split('.');
    dynamic current = json;
    for (final part in parts) {
      if (current is Map && current.containsKey(part)) {
        current = current[part];
      } else {
        return null;
      }
    }
    return current;
  }

  void _log(String msg) {
    if (AppConstants.kApiDebug) {
      // ignore: avoid_print
      print(msg);
    }
  }
}
