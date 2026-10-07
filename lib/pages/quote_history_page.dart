// lib/pages/quote_history_page.dart
import 'package:flutter/material.dart';

import '../db/quote_dao.dart';
import '../models/quote.dart';
import 'quote_detail_page.dart';

class QuoteHistoryPage extends StatefulWidget {
  const QuoteHistoryPage({super.key});

  @override
  State<QuoteHistoryPage> createState() => _QuoteHistoryPageState();
}

class _QuoteHistoryPageState extends State<QuoteHistoryPage> {
  final QuoteDao _dao = QuoteDao();
  final TextEditingController _searchCtrl = TextEditingController();

  List<Quote> _list = [];
  bool _loading = true;
  String _orderBy = 'updated_at DESC';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _dao.getSavedList(
      orderBy: _orderBy,
      keyword: _searchCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _list = list;
      _loading = false;
    });
  }

  Future<void> _delete(Quote q) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除报价单'),
        content: Text('「${q.name ?? "未命名"}」将被永久删除，不可恢复。'),
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
    await _dao.deleteQuote(q.id!);
    _load();
  }

  void _showSortMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('按最后修改时间'),
              trailing: _orderBy == 'updated_at DESC'
                  ? const Icon(Icons.check, color: Colors.blue)
                  : null,
              onTap: () {
                setState(() => _orderBy = 'updated_at DESC');
                Navigator.pop(ctx);
                _load();
              },
            ),
            ListTile(
              title: const Text('按创建时间'),
              trailing: _orderBy == 'created_at DESC'
                  ? const Icon(Icons.check, color: Colors.blue)
                  : null,
              onTap: () {
                setState(() => _orderBy = 'created_at DESC');
                Navigator.pop(ctx);
                _load();
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    String p(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${p(dt.month)}-${p(dt.day)} ${p(dt.hour)}:${p(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('历史报价单'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sort),
            tooltip: '排序',
            onPressed: _showSortMenu,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: '🔍 搜客户名、报价单名称',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _load();
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) {
                setState(() {});
                _load();
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _list.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history, size: 64, color: Colors.grey),
                        SizedBox(height: 8),
                        Text('暂无历史报价单', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _list.length,
                    itemBuilder: (ctx, i) {
                      final q = _list[i];
                      return Dismissible(
                        key: ValueKey('quote_${q.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (_) async {
                          await _delete(q);
                          return false;
                        },
                        child: Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: ListTile(
                            title: Text(q.name ?? '未命名'),
                            subtitle: Text(
                              '${q.customer?.isNotEmpty == true ? "客户：${q.customer} · " : ""}共 ${q.itemCount} 件 · ${_formatTime(q.createdAt)}',
                            ),
                            trailing: Text(
                              '¥${q.totalPrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      QuoteDetailPage(quoteId: q.id!),
                                ),
                              );
                              _load();
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
