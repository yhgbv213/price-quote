// lib/pages/settings_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import 'about_page.dart';
import 'api_sources_page.dart';

import '../db/database_helper.dart';
import '../providers/product_provider.dart';
import '../providers/quote_provider.dart';
import '../providers/api_source_provider.dart';

import 'backup_page.dart';

import 'cache_manage_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  // ============ 主题外观选择 ============
  Future<void> _pickTheme(BuildContext context) async {
    final provider = context.read<SettingsProvider>();
    final current = provider.themeMode;

    final picked = await showModalBottomSheet<ThemeMode>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '主题外观',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            RadioGroup<ThemeMode>(
              groupValue: current,
              onChanged: (v) => Navigator.pop(ctx, v),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<ThemeMode>(
                    title: Text('跟随系统'),
                    value: ThemeMode.system,
                  ),
                  RadioListTile<ThemeMode>(
                    title: Text('浅色'),
                    value: ThemeMode.light,
                  ),
                  RadioListTile<ThemeMode>(
                    title: Text('深色'),
                    value: ThemeMode.dark,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (picked != null) {
      await provider.setThemeMode(picked);
    }
  }

  // ============ 清空所有数据 ============
  Future<void> _clearAllData(BuildContext context) async {
    // 提前取出 provider 引用
    final productProvider = context.read<ProductProvider>();
    final quoteProvider = context.read<QuoteProvider>();
    final apiSourceProvider = context.read<ApiSourceProvider>();
    final settingsProvider = context.read<SettingsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    String inputText = '';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('清空所有数据'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '此操作将删除：\n'
                  '• 所有商品\n'
                  '• 回收站\n'
                  '• 价格历史\n'
                  '• 条码缓存\n'
                  '• 所有报价单\n'
                  '• 自定义 API 配置\n\n'
                  '内置 API 源与设置将重置为默认值。此操作不可恢复。\n\n'
                  '⚠️ 此操作同时视为您撤回对「用户协议与免责声明」的同意。',
                  style: TextStyle(fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 16),
                const Text(
                  '请输入「确认清空」四个字以继续：',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                TextField(
                  autofocus: true,
                  onChanged: (v) {
                    setDialogState(() => inputText = v);
                  },
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '确认清空',
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: inputText.trim() == '确认清空'
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: Text(
                '确认清空',
                style: TextStyle(
                  color: inputText.trim() == '确认清空' ? Colors.red : Colors.grey,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    // 执行清空
    await DatabaseHelper().clearAllData();

    // 刷新所有 Provider
    await productProvider.loadProducts();
    await quoteProvider.loadOrCreateDraft();
    await apiSourceProvider.loadAll();
    await settingsProvider.load();

    messenger.showSnackBar(const SnackBar(content: Text('已清空所有数据')));
    navigator.popUntil((route) => route.isFirst);
  }

  String _themeLabel(ThemeMode m) {
    switch (m) {
      case ThemeMode.system:
        return '跟随系统';
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          // ============ 外观与显示 ============
          _sectionTitle('外观与显示'),
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: const Text('主题外观'),
            subtitle: Text(_themeLabel(settings.themeMode)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickTheme(context),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.dashboard_outlined),
            title: const Text('显示数据概览'),
            subtitle: const Text('首页底部显示商品数与总价值'),
            value: settings.showDashboard,
            onChanged: (v) => settings.setShowDashboard(v),
          ),

          const Divider(),

          // ============ 数据与查询 ============
          _sectionTitle('数据与查询'),
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('查询数据源'),
            subtitle: const Text('管理 API 源、优先级、密钥'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ApiSourcesPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('缓存管理'),
            subtitle: const Text('上限、过期时间、导出'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CacheManagePage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('数据备份'),
            subtitle: const Text('商品数据导出与导入'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BackupPage()),
              );
            },
          ),

          const Divider(),

          // ============ 录入偏好 ============
          _sectionTitle('录入偏好'),
          SwitchListTile(
            secondary: const Icon(Icons.image_outlined),
            title: const Text('连续添加沿用上一张图片'),
            subtitle: Text(
              settings.imageReuseChoice == 'reuse'
                  ? '已开启：连续录入自动沿用上一张图'
                  : '关闭时：首次遇到会询问',
            ),
            value: settings.imageReuseChoice == 'reuse',
            onChanged: (v) {
              settings.setImageReuseChoice(v ? 'reuse' : '');
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.qr_code_scanner),
            title: const Text('保存并继续后自动扫码'),
            subtitle: const Text('开启后：保存并继续 → 直接打开扫码'),
            value: settings.autoScanAfterSaveContinue,
            onChanged: (v) => settings.setAutoScanAfterSaveContinue(v),
          ),

          const Divider(),

          // ============ 数据安全 ============
          _sectionTitle('数据安全'),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('清空所有数据', style: TextStyle(color: Colors.red)),
            subtitle: const Text('删除所有商品、报价单、缓存等'),
            onTap: () => _clearAllData(context),
          ),

          const Divider(),

          // ============ 关于 ============
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutPage()),
              );
            },
          ),

          const SizedBox(height: 24),
          const Center(
            child: Text(
              '商品报价 v1.0.1',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          color: Colors.grey,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
