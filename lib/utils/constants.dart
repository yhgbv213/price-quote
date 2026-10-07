// lib/utils/constants.dart
import 'package:flutter/foundation.dart';

class AppConstants {
  // ============ 数据库 ============
  static const int dbVersion = 10;

  // ============ 缓存 ============
  static const int cacheMaxCount = 2000;
  static const int cacheExpireDays = 180;

  // ============ 回收站 ============
  static const int recycleMaxDays = 30;
  static const int recycleMaxCount = 500;
  static const int recycleMaxBytes = 100 * 1024 * 1024; // 100MB

  // ============ 报价单 ============
  static const int quoteMaxItems = 200;
  static const int quoteMaxCount = 500;

  // ============ 价格历史 ============
  static const int priceHistoryMaxPerProduct = 20;

  // ============ 图片 ============
  static const int imageMaxLongSide = 1080;
  static const int imageQuality = 85;
  static const int imageMaxLongSideLowEnd = 720;
  static const int imageQualityLowEnd = 60;
  static const int imageMaxTotalBytes = 500 * 1024 * 1024; // 500MB
  static const int imageDownloadConcurrency = 3;

  // ============ 条码 ============
  static const String autoBarcodePrefix = 'AUTO_';

  // ============ 防抖与搜索 ============
  static const int debounceMs = 300;
  static const int searchLimit = 50;

  // ============ 默认值 ============
  static const String defaultSortMode = 'update_time_desc';
  static const String defaultThemeMode = 'system';

  // ============ 免责声明 ============
  static const String disclaimerVersion = '1.0';

  // ============ 调试 ============
  /// 调试日志开关：debug 自动开，release 自动关（无需手工切换）
  static const bool kApiDebug = kDebugMode;
}
