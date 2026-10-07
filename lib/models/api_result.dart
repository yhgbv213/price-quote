// lib/models/api_result.dart
class ApiResult {
  final bool success;
  final String? name;
  final String? brand;
  final String? spec;
  final String? imageUrl;
  final double? price;
  final String? rawResponse;
  final String? errorMessage;
  final String? sourceName;

  // V5.1 新增：来源与耗时
  final bool isFromCache; // 是否来自缓存
  final int elapsedMs; // 请求耗时（毫秒）
  final int? cacheAgeMs; // 缓存年龄（毫秒，仅缓存时有值）

  ApiResult({
    required this.success,
    this.name,
    this.brand,
    this.spec,
    this.imageUrl,
    this.price,
    this.rawResponse,
    this.errorMessage,
    this.sourceName,
    this.isFromCache = false,
    this.elapsedMs = 0,
    this.cacheAgeMs,
  });

  factory ApiResult.ok({
    String? name,
    String? brand,
    String? spec,
    String? imageUrl,
    double? price,
    String? rawResponse,
    required String sourceName,
    bool isFromCache = false,
    int elapsedMs = 0,
    int? cacheAgeMs,
  }) {
    return ApiResult(
      success: true,
      name: name,
      brand: brand,
      spec: spec,
      imageUrl: imageUrl,
      price: price,
      rawResponse: rawResponse,
      sourceName: sourceName,
      isFromCache: isFromCache,
      elapsedMs: elapsedMs,
      cacheAgeMs: cacheAgeMs,
    );
  }

  factory ApiResult.fail(String msg) {
    return ApiResult(success: false, errorMessage: msg);
  }

  bool get nameIsChinese {
    if (name == null || name!.isEmpty) return false;
    return RegExp(r'[\u4e00-\u9fa5]').hasMatch(name!);
  }

  /// 格式化的缓存年龄（如 "3天前" / "2小时前" / "5分钟前"）
  String? get cacheAgeText {
    if (cacheAgeMs == null) return null;
    final ms = cacheAgeMs!;
    if (ms < 60 * 1000) return '刚刚';
    if (ms < 60 * 60 * 1000) {
      return '${(ms / 60000).floor()}分钟前';
    }
    if (ms < 24 * 60 * 60 * 1000) {
      return '${(ms / 3600000).floor()}小时前';
    }
    return '${(ms / 86400000).floor()}天前';
  }

  /// 格式化的耗时（如 "0.8s" / "1.2s"）
  String get elapsedText {
    return '${(elapsedMs / 1000).toStringAsFixed(1)}s';
  }
}
