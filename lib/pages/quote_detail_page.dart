// lib/pages/quote_detail_page.dart
import 'package:flutter/material.dart';

import '../db/quote_dao.dart';
import '../db/quote_item_dao.dart';
import '../models/quote.dart';
import '../models/quote_item.dart';

import '../services/quote_export_service.dart';

class QuoteDetailPage extends StatefulWidget {
  final int quoteId;
  const QuoteDetailPage({super.key, required this.quoteId});

  @override
  State<QuoteDetailPage> createState() => _QuoteDetailPageState();
}

class _QuoteDetailPageState extends State<QuoteDetailPage> {
  final QuoteDao _quoteDao = QuoteDao();
  final QuoteItemDao _itemDao = QuoteItemDao();

  Quote? _quote;
  List<QuoteItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final q = await _quoteDao.getById(widget.quoteId);
    final items = await _itemDao.getByQuoteId(widget.quoteId);
    if (!mounted) return;
    setState(() {
      _quote = q;
      _items = items;
      _loading = false;
    });
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除整单'),
        content: const Text('该报价单及其明细将被永久删除，不可恢复。确认吗？'),
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
    await _quoteDao.deleteQuote(widget.quoteId);
    if (mounted) Navigator.pop(context);
  }

  // ============ 导出 Excel ============
  Future<void> _export() async {
    if (_quote == null || _items.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('报价单为空，无内容可导出')));
      return;
    }
    try {
      await QuoteExportService().exportAndShare(_quote!, _items);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导出失败: $e')));
    }
  }

  String _formatTime(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    String p(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${p(dt.month)}-${p(dt.day)} ${p(dt.hour)}:${p(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final q = _quote;
    if (q == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('报价单详情')),
        body: const Center(child: Text('报价单不存在')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(q.name ?? '报价单详情'),
        actions: [
          // 导出
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: '导出 Excel',
            onPressed: _export,
          ),
          // 删除
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除整单',
            onPressed: _delete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // 信息区
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow('报价单名称', q.name ?? '未命名'),
                  if (q.customer?.isNotEmpty == true)
                    _infoRow('客户', q.customer!),
                  if (q.note?.isNotEmpty == true) _infoRow('备注', q.note!),
                  _infoRow('创建时间', _formatTime(q.createdAt)),
                  _infoRow('最后修改', _formatTime(q.updatedAt)),
                  const Divider(),
                  Row(
                    children: [
                      const Text('总价', style: TextStyle(fontSize: 15)),
                      const Spacer(),
                      Text(
                        '¥${q.totalPrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '共 ${q.itemCount} 件',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text(
              '明细',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
          // 明细
          ..._items.map(
            (item) => Card(
              margin: const EdgeInsets.symmetric(vertical: 3),
              child: ListTile(
                title: Text(item.name),
                subtitle: Text(
                  '${item.spec?.isNotEmpty == true ? "${item.spec} · " : ""}¥${item.unitPrice.toStringAsFixed(2)} × ${item.quantity}',
                ),
                trailing: Text(
                  '¥${item.subtotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}
