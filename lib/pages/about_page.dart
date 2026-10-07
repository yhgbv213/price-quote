// lib/pages/about_page.dart
import 'package:flutter/material.dart';

import 'disclaimer_page.dart';

// ignore_for_file: prefer_const_constructors
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const String _appName = '商品报价';
  static const String _version = '1.0.1';
  static const String _buildNumber = '3';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 24),
          // 应用图标占位
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.shopping_bag,
                size: 44,
                color: Colors.blue,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              _appName,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              '版本 $_version (build $_buildNumber)',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          const SizedBox(height: 32),

          // ============ 隐私说明 ============
          _card(
            title: '隐私说明',
            content: const Text(
              '本应用是纯单机工具，所有数据（商品、报价单、缓存、API配置）'
              '均保存在您手机的本地数据库中，不会上传到任何服务器。\n\n'
              '仅在您主动使用"联网查询"功能时，才会向您配置的 API 数据源'
              '（默认 Open Food Facts）发送条码。API 配置中的密钥信息默认'
              '掩码显示，且永不导出、永不分享。\n\n'
              '您可以随时在"设置 → 清空所有数据"中彻底删除所有本地数据。',
              style: TextStyle(fontSize: 14, height: 1.6),
            ),
          ),

          const SizedBox(height: 12),

          // ============ 用户协议与免责声明 ============
          Card(
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('用户协议与免责声明'),
              subtitle: const Text('点击查看完整内容'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DisclaimerFullPage()),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          // ============ 开源许可 ============
          // 用 Flutter 官方内置许可页：自动收集全部 pub 依赖的 LICENSE，
          // 零依赖、零维护，不会漏掉任何组件。
          Card(
            child: ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('开源许可'),
              subtitle: const Text('查看本应用使用的全部开源组件许可'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLicensePage(
                context: context,
                applicationName: _appName,
                applicationVersion: '$_version (build $_buildNumber)',
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ============ 联系方式 ============
          _card(
            title: '联系方式',
            content: const Text(
              '使用中遇到问题或有建议，欢迎反馈。\n\n'
              '邮箱：（待填写）',
              style: TextStyle(fontSize: 14, height: 1.6),
            ),
          ),

          const SizedBox(height: 32),
          const Center(
            child: Text(
              '© 2026 商品报价',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _card({required String title, required Widget content}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            content,
          ],
        ),
      ),
    );
  }
}
