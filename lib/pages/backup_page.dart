// lib/pages/backup_page.dart
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/product_provider.dart';
import '../services/backup_service.dart';

class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  Future<void> _export(BuildContext context) async {
    final productProvider = context.read<ProductProvider>();
    final messenger = ScaffoldMessenger.of(context);

    final all = productProvider.allProducts;
    if (all.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('暂无商品数据，无法导出')));
      return;
    }

    // 隐私提示
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导出商品数据'),
        content: const Text(
          '文件包含你的商品、价格历史、分类设置。\n'
          '不包含图片、缓存、API 配置、报价单。\n\n'
          '请妥善保管导出文件。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('导出'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      messenger.showSnackBar(const SnackBar(content: Text('正在生成备份文件...')));
      await BackupService().exportAndShare();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导出失败: $e')));
    }
  }

  Future<void> _import(BuildContext context) async {
    final productProvider = context.read<ProductProvider>();
    final messenger = ScaffoldMessenger.of(context);

    // 1. 选文件
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('选择文件失败: $e')));
      return;
    }
    if (picked == null || picked.files.isEmpty) return;

    final bytes = picked.files.first.bytes;
    if (bytes == null) {
      messenger.showSnackBar(const SnackBar(content: Text('无法读取文件内容')));
      return;
    }

    // 2. 解析 + 生成预览（不写库）
    final service = BackupService();
    BackupImportPreview preview;
    try {
      preview = await service.previewImport(utf8.decode(bytes));
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导入失败：${e.message}')));
      return;
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导入失败：文件解析错误（$e）')));
      return;
    }

    if (preview.total == 0) {
      messenger.showSnackBar(const SnackBar(content: Text('文件中没有可导入的商品')));
      return;
    }

    // 3. 预览确认
    if (!context.mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入预览'),
        content: Text(
          '文件含 ${preview.total} 条商品：\n'
          '├── 新增 ${preview.added} 条\n'
          '├── 更新 ${preview.updated} 条（本地较旧）\n'
          '└── 跳过 ${preview.skipped} 条（本地较新）\n\n'
          '同条码按更新时间较新覆盖；导入的商品不含图片，需要重新拍照。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('开始导入'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    // 4. 执行导入并刷新首页数据
    try {
      final result = await service.applyImport(preview);
      await productProvider.loadProducts();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '导入完成：新增 ${result.added} / 更新 ${result.updated} / 跳过 ${result.skipped}',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导入失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final productProvider = context.watch<ProductProvider>();
    final count = productProvider.allProducts.length;

    return Scaffold(
      appBar: AppBar(title: const Text('数据备份')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '当前数据',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text('商品：$count 条'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('导出商品数据'),
            subtitle: const Text('导出为 JSON 文件，可分享到微信/网盘'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _export(context),
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('导入商品数据'),
            subtitle: const Text('从 JSON 备份文件恢复商品与价格历史'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _import(context),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '说明：\n'
              '• 导出内容：商品、价格历史、分类设置\n'
              '• 不包含：图片、缓存、API 配置、报价单\n'
              '• 导入时同条码按更新时间较新覆盖，不同条码追加\n'
              '• 导入后商品无图片（image_source = none）',
              style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}
