// lib/pages/recycle_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/recycle_item.dart';
import '../providers/product_provider.dart';
import '../utils/constants.dart';

class RecyclePage extends StatefulWidget {
  const RecyclePage({super.key});

  @override
  State<RecyclePage> createState() => _RecyclePageState();
}

class _RecyclePageState extends State<RecyclePage> {
  List<RecycleItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await context.read<ProductProvider>().loadRecycleItems();
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  // 恢复
  Future<void> _restore(RecycleItem item) async {
    final provider = context.read<ProductProvider>();
    final exists = await provider.checkBarcodeExists(item.barcode);

    if (exists) {
      if (!mounted) return;

      // 普通条码冲突：无法恢复（文档 6.1「冲突时强提示」）
      if (!item.barcode.startsWith(AppConstants.autoBarcodePrefix)) {
        _showDialog('条码冲突', '主表中已存在条码「${item.barcode}」的商品，无法恢复。');
        return;
      }

      // AUTO_ 序号被占用：询问是否分配新序号（文档 6.4 场景 C）
      final assign = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('序号已被占用'),
          content: Text('序号「${item.barcode}」已被其他商品使用。\n是否分配新序号后恢复？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('分配新序号'),
            ),
          ],
        ),
      );
      if (assign != true || !mounted) return;
    }

    try {
      final newBarcode = await provider.restoreFromRecycleBin(
        item,
        assignNewBarcodeIfConflict: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newBarcode == item.barcode ? '已恢复' : '已恢复（新序号 $newBarcode）',
          ),
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      _showDialog('恢复失败', '$e');
    }
  }

  // 永久删除
  Future<void> _deleteForever(RecycleItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('永久删除'),
        content: Text('「${item.name}」将被永久删除，不可恢复。确认删除？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;
    await context.read<ProductProvider>().deleteRecycleItem(item);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已永久删除')));
    _load();
  }

  // 清空
  Future<void> _clearAll() async {
    if (_items.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空回收站'),
        content: Text('将永久删除 ${_items.length} 条记录，不可恢复。确认清空？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;
    await context.read<ProductProvider>().clearRecycleBin();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('回收站已清空')));
    _load();
  }

  void _showDialog(String title, String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站'),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: '清空回收站',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('回收站是空的', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (ctx, i) {
                      final item = _items[i];
                      final categoryText = item.category.isEmpty
                          ? '未分类'
                          : item.category;
                      return Dismissible(
                        key: ValueKey('recycle_${item.id}'),
                        background: Container(
                          color: Colors.green,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 20),
                          child: const Icon(Icons.restore, color: Colors.white),
                        ),
                        secondaryBackground: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(
                            Icons.delete_forever,
                            color: Colors.white,
                          ),
                        ),
                        confirmDismiss: (direction) async {
                          if (direction == DismissDirection.startToEnd) {
                            // 右滑 → 恢复
                            await _restore(item);
                            return false;
                          } else {
                            // 左滑 → 永久删除
                            await _deleteForever(item);
                            return false;
                          }
                        },
                        child: Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Colors.grey,
                              child: Icon(Icons.recycling, color: Colors.white),
                            ),
                            title: Text(item.name),
                            subtitle: Text(
                              '条码: ${item.barcode}\n分类: $categoryText',
                            ),
                            isThreeLine: true,
                            trailing: Text(
                              '¥${item.sellingPrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // 底部提示
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.shade900
                      : Colors.grey.shade100,
                  child: const Text(
                    '回收站最多保留 500 条或 100MB，30 天后自动清空',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
    );
  }
}
