// lib/pages/api_sources_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/api_source.dart';
import '../providers/api_source_provider.dart';
import '../utils/mask_util.dart';
import 'api_source_edit_page.dart';

class ApiSourcesPage extends StatefulWidget {
  const ApiSourcesPage({super.key});

  @override
  State<ApiSourcesPage> createState() => _ApiSourcesPageState();
}

class _ApiSourcesPageState extends State<ApiSourcesPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ApiSourceProvider>().loadAll();
    });
  }

  // ============ 应用预设 ============
  Future<void> _applyPreset(String preset) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('切换模式'),
        content: Text('切换到「$preset」将覆盖当前数据源配置，是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final provider = context.read<ApiSourceProvider>();
    final ok = await provider.applyPreset(preset);

    if (!mounted) return;
    if (!ok && preset == '标准模式') {
      final reAdd = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('阿里云源已被删除'),
          content: const Text('是否重新添加模板源？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('添加'),
            ),
          ],
        ),
      );
      if (reAdd == true && mounted) {
        await provider.reAddAliYun();
        await provider.applyPreset(preset);
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已切换到「$preset」')));
    }
  }

  // ============ 删除 ============
  Future<void> _delete(ApiSource source) async {
    final provider = context.read<ApiSourceProvider>();

    // // 先检查能不能删
    // final canDeleteErr = await provider.deleteSource; // 只读引用，不执行
    // // ↑ 这行没用，改为先检查
    if (source.isProtected) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('免费兜底源不可删除，防止无源可用')));
      }
      return;
    }
    if (source.enabled) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('请先禁用该数据源，再执行删除')));
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除数据源'),
        content: Text('删除「${source.name}」后不可恢复，确认删除？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final err = await provider.deleteSource(source);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已删除')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ApiSourceProvider>();
    final currentPreset = provider.currentPresetName();

    return Scaffold(
      appBar: AppBar(
        title: const Text('查询数据源'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加数据源',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ApiSourceEditPage()),
              );
            },
          ),
        ],
      ),
      body: provider.loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // ============ 预设模板 ============
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    '预设模板',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _presetChip('免费模式', currentPreset),
                      _presetChip('标准模式', currentPreset),
                      _presetChip('离线模式', currentPreset),
                      Chip(
                        label: const Text('自定义模式'),
                        backgroundColor: currentPreset == '自定义模式'
                            ? _selectedChipColor()
                            : null,
                        avatar: currentPreset == '自定义模式'
                            ? const Icon(Icons.check, size: 16)
                            : null,
                      ),
                    ],
                  ),
                ),

                const Divider(height: 32),

                // ============ 数据源列表 ============
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    '数据源列表（按优先级从高到低）',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ...provider.sources.map((s) => _buildSourceCard(s)),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  /// 选中态底色：浅色用浅蓝，深色用深蓝。
  /// 深色主题下标签文字是白色，若仍用浅蓝底会几乎看不清。
  Color _selectedChipColor() {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.blue.shade900
        : Colors.blue.shade100;
  }

  Widget _presetChip(String name, String current) {
    final isSelected = current == name;
    return ActionChip(
      label: Text(name),
      avatar: isSelected ? const Icon(Icons.check, size: 16) : null,
      backgroundColor: isSelected ? _selectedChipColor() : null,
      onPressed: () => _applyPreset(name),
    );
  }

  Widget _buildSourceCard(ApiSource s) {
    final provider = context.read<ApiSourceProvider>();
    final maskedUrl = MaskUtil.maskUrl(s.baseUrl);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: [
          ListTile(
            title: Row(
              children: [
                Expanded(child: Text(s.name)),
                if (s.isProtected)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.lock, size: 14, color: Colors.grey),
                  ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                maskedUrl,
                style: const TextStyle(fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            trailing: Switch(
              value: s.enabled,
              onChanged: (_) async {
                await provider.toggleEnabled(s);
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('已更新查询策略')));
                }
              },
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ApiSourceEditPage(source: s)),
              );
            },
          ),
          // 底部操作
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('编辑'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ApiSourceEditPage(source: s),
                    ),
                  );
                },
              ),
              TextButton.icon(
                icon: const Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: Colors.red,
                ),
                label: const Text('删除', style: TextStyle(color: Colors.red)),
                onPressed: () => _delete(s),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
    );
  }
}
