// lib/utils/mask_util.dart
class MaskUtil {
  /// 掩码敏感字符串
  /// - 长度 ≤ 6：完全掩码为 ******
  /// - 长度 > 6：保留首尾各 2 位，中间用 **** 替代
  ///   例：ak1234567890ab3f → ak****3f
  static String mask(String? text) {
    if (text == null || text.isEmpty) return '';
    if (text.length <= 6) return '******';
    final head = text.substring(0, 2);
    final tail = text.substring(text.length - 2);
    return '$head****$tail';
  }

  /// 判断 URL 中是否含有疑似密钥参数
  static bool urlHasKey(String url) {
    final lower = url.toLowerCase();
    return lower.contains('key=') ||
        lower.contains('token=') ||
        lower.contains('secret=') ||
        lower.contains('apikey=') ||
        lower.contains('api_key=') ||
        lower.contains('access_token=');
  }

  /// 掩码 URL 中疑似密钥参数的值
  /// 例：https://api.com/?key=abcdefghij → https://api.com/?key=ab****ij
  static String maskUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (!urlHasKey(url)) return url;

    // 匹配 key=xxx / token=xxx 等
    final reg = RegExp(
      r'(key|token|secret|apikey|api_key|access_token)=([^&\s]+)',
      caseSensitive: false,
    );
    return url.replaceAllMapped(reg, (m) {
      final name = m.group(1)!;
      final value = m.group(2)!;
      return '$name=${mask(value)}';
    });
  }

  /// 判断某字段是否敏感（用于 UI 是否显示 👁️ 按钮）
  static bool isSensitiveField(String fieldName) {
    return fieldName == 'headers' ||
        fieldName == 'paramsTemplate' ||
        fieldName == 'bodyTemplate' ||
        fieldName == 'baseUrl';
  }
}
