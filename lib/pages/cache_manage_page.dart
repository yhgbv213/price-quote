// lib/pages/cache_manage_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/cache_provider.dart';

class CacheManagePage extends StatefulWidget {
  const CacheManagePage({super.key});

  @override
  State<CacheManagePage> createState() => _CacheManagePageState();
}

class _CacheManagePageState extends State<CacheManagePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CacheProvider>().load();
    });
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  String _maxCountLabel(int v) {
    if (v < 0) return '不限';
    return '$v';
  }

  String _expireLabel(int v) {
    if (v < 0) return '永久';
    return '$v天';
  }

  // ============ 调整上限 ============
  Future<void> _pickMaxCount(CacheProvider provider) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '缓存上限',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            RadioGroup<int>(
              groupValue: provider.maxCount,
              onChanged: (val) => Navigator.pop(ctx, val),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final v in CacheProvider.maxCountOptions)
                    RadioListTile<int>(
                      title: Text(_maxCountLabel(v)),
                      value: v,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (picked == null || picked == provider.maxCount) return;

    final deleted = await provider.setMaxCount(picked);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(deleted > 0 ? '已清理 $deleted 条缓存' : '已更新缓存上限')),
    );
  }

  // ============ 调整过期时间 ============
  Future<void> _pickExpire(CacheProvider provider) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '缓存过期时间',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            RadioGroup<int>(
              groupValue: provider.expireDays,
              onChanged: (val) => Navigator.pop(ctx, val),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final v in CacheProvider.expireDaysOptions)
                    RadioListTile<int>(
                      title: Text(_expireLabel(v)),
                      value: v,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (picked == null || picked == provider.expireDays) return;

    final deleted = await provider.setExpireDays(picked);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(deleted > 0 ? '已清理 $deleted 条过期记录' : '已更新过期时间')),
    );
  }

  // ============ 导入 ============
  Future<void> _import(CacheProvider provider) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入缓存'),
        content: const Text(
          '从 JSON 文件合并缓存。\n\n'
          '规则：\n'
          '• 本地库存条码的缓存优先保留，不被覆盖\n'
          '• 非库存条码：导入数据时间较新则覆盖本地\n'
          '• 超出上限时按 LRU 淘汰\n\n'
          '继续导入？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('选择文件'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      final result = await provider.importFromFile();
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导入完成'),
          content: Text(
            '新增：${result.added}\n'
            '更新：${result.updated}\n'
            '跳过（本地更新）：${result.skipped}',
            style: const TextStyle(fontSize: 15, height: 1.8),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导入失败: $e')));
    }
  }

  // ============ 导出 ============
  Future<void> _export(CacheProvider provider) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导出缓存'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '你即将导出的缓存包含扫描过的商品条码记录。',
                style: TextStyle(fontSize: 14, height: 1.6),
              ),
              SizedBox(height: 12),
              Text(
                '请确认：',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 6),
              Text(
                '• 接收方可信\n'
                '• 分享行为符合你所使用 API 的服务条款\n'
                '• 不用于商业转售',
                style: TextStyle(fontSize: 14, height: 1.8),
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
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认导出'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await provider.exportAndShare();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导出失败: $e')));
    }
  }

  // ============ 清空 ============
  Future<void> _clearAll(CacheProvider provider) async {
    final input = ValueNotifier<String>('');
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => ValueListenableBuilder<String>(
        valueListenable: input,
        builder: (ctx, val, _) => AlertDialog(
          title: const Text('清空缓存'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('将删除所有缓存记录（含库存条码缓存），确认？'),
              const SizedBox(height: 12),
              const Text(
                '请输入「确认清空」：',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              TextField(
                autofocus: true,
                onChanged: (v) => input.value = v,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: val.trim() == '确认清空'
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: Text(
                '清空',
                style: TextStyle(
                  color: val.trim() == '确认清空' ? Colors.red : Colors.grey,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirm != true || !mounted) return;

    final count = await provider.clearAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已清空 $count 条缓存')));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CacheProvider>();
    final stats = provider.stats;

    return Scaffold(
      appBar: AppBar(title: const Text('缓存管理')),
      body: provider.loading || stats == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // ============ 当前占用 ============
                Card(
                  margin: const EdgeInsets.all(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '当前缓存',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${stats.totalCount} 条 / 占用 ${_formatBytes(stats.totalBytes)}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '库存条码缓存：${stats.stockCount} 条（优先保留）',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        Text(
                          '其他缓存：${stats.otherCount} 条',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ============ 缓存总开关 ============
                SwitchListTile(
                  secondary: const Icon(Icons.cached),
                  title: const Text('启用缓存'),
                  subtitle: Text(
                    provider.cacheEnabled
                        ? '查询优先走缓存（0ms 命中），新数据自动写入'
                        : '已关闭：不读也不写缓存，已有缓存仍保留',
                  ),
                  value: provider.cacheEnabled,
                  onChanged: (v) async {
                    await provider.setCacheEnabled(v);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          v ? '缓存已开启' : '缓存已关闭（已有缓存保留）',
                        ),
                      ),
                    );
                  },
                ),

                const Divider(),

                // ============ 上限 ============
                ListTile(
                  leading: const Icon(Icons.storage),
                  title: const Text('缓存上限'),
                  subtitle: Text(_maxCountLabel(provider.maxCount)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _pickMaxCount(provider),
                ),

                // ============ 过期时间 ============
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: const Text('过期时间'),
                  subtitle: Text(_expireLabel(provider.expireDays)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _pickExpire(provider),
                ),

                const Divider(),

                // ============ 导出 ============
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: const Text('导出缓存'),
                  subtitle: const Text('生成 JSON 文件，可分享给他人'),
                  onTap: () => _export(provider),
                ),

                // ============ 导入 ============
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('导入缓存'),
                  subtitle: const Text('从 JSON 文件合并缓存（库存优先）'),
                  onTap: () => _import(provider),
                ),

                const Divider(),

                // ============ 清空 ============
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text(
                    '清空缓存',
                    style: TextStyle(color: Colors.red),
                  ),
                  subtitle: const Text('删除所有缓存记录，包括库存条码'),
                  onTap: () => _clearAll(provider),
                ),

                const SizedBox(height: 24),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '说明：\n'
                    '• 库存条码（你商品库里的）缓存优先保留，不轻易淘汰\n'
                    '• 非库存条码缓存按 LRU 规则淘汰\n'
                    '• 库存条码缓存不受过期时间限制\n'
                    '• 缓存可导出分享给他人，实现"众包省钱"',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      height: 1.6,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
