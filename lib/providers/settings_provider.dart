// lib/providers/settings_provider.dart
import 'package:flutter/material.dart';

import '../db/app_settings_dao.dart';
import '../utils/constants.dart';

/// 免责声明版本（单一来源：AppConstants.disclaimerVersion）
const String kDisclaimerVersion = AppConstants.disclaimerVersion;

class SettingsProvider extends ChangeNotifier {
  final AppSettingsDao _dao = AppSettingsDao();

  // ============ 状态 ============
  ThemeMode _themeMode = ThemeMode.system;
  bool _showDashboard = true;
  bool _loaded = false;
  String _imageReuseChoice = '';
  bool _freeModeTipShown = false;
  bool _autoScanAfterSaveContinue = false;

  // 免责声明
  int _disclaimerAgreedAt = 0;
  String _disclaimerVersion = '';

  // ============ Getter ============
  ThemeMode get themeMode => _themeMode;
  bool get showDashboard => _showDashboard;
  bool get loaded => _loaded;
  String get imageReuseChoice => _imageReuseChoice;
  bool get freeModeTipShown => _freeModeTipShown;
  bool get autoScanAfterSaveContinue => _autoScanAfterSaveContinue;
  int get disclaimerAgreedAt => _disclaimerAgreedAt;
  String get disclaimerVersion => _disclaimerVersion;

  /// 是否需要重新同意免责声明（未同意 或 协议版本变了）
  bool get needsDisclaimerAgreement {
    if (_disclaimerAgreedAt == 0) return true;
    return _disclaimerVersion != kDisclaimerVersion;
  }

  // ============ 加载 ============
  Future<void> load() async {
    final themeStr =
        await _dao.get('theme_mode') ?? AppConstants.defaultThemeMode;
    final dashStr = await _dao.get('show_dashboard') ?? 'true';
    _imageReuseChoice = await _dao.get('image_reuse_choice') ?? '';
    _freeModeTipShown =
        (await _dao.get('free_mode_tip_shown') ?? 'false') == 'true';
    _autoScanAfterSaveContinue =
        (await _dao.get('auto_scan_after_save_continue') ?? 'false') == 'true';

    _disclaimerAgreedAt =
        int.tryParse(await _dao.get('disclaimer_agreed_at') ?? '0') ?? 0;
    _disclaimerVersion = await _dao.get('disclaimer_version') ?? '';

    _themeMode = _parseTheme(themeStr);
    _showDashboard = dashStr == 'true';
    _loaded = true;
    notifyListeners();
  }

  // ============ 主题外观 ============
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    await _dao.set('theme_mode', _themeToString(mode));
  }

  // ============ 数据概览开关 ============
  Future<void> setShowDashboard(bool v) async {
    _showDashboard = v;
    notifyListeners();
    await _dao.set('show_dashboard', v ? 'true' : 'false');
  }

  // ============ 图片沿用偏好 ============
  Future<void> setImageReuseChoice(String v) async {
    _imageReuseChoice = v;
    notifyListeners();
    await _dao.set('image_reuse_choice', v);
  }

  // ============ 免费模式首次提示 ============
  Future<void> markFreeModeTipShown() async {
    _freeModeTipShown = true;
    notifyListeners();
    await _dao.set('free_mode_tip_shown', 'true');
  }

  // ============ 保存并继续后自动扫码 ============
  Future<void> setAutoScanAfterSaveContinue(bool v) async {
    _autoScanAfterSaveContinue = v;
    notifyListeners();
    await _dao.set('auto_scan_after_save_continue', v ? 'true' : 'false');
  }

  // ============ 免责声明同意 ============
  Future<void> agreeDisclaimer() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    _disclaimerAgreedAt = now;
    _disclaimerVersion = kDisclaimerVersion;
    notifyListeners();
    await _dao.set('disclaimer_agreed_at', now.toString());
    await _dao.set('disclaimer_version', kDisclaimerVersion);
  }

  // ============ 工具 ============
  ThemeMode _parseTheme(String s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _themeToString(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
