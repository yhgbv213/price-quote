// lib/pages/quote_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../providers/product_provider.dart';
import '../providers/quote_provider.dart';
import '../utils/app_toast.dart';
import '../utils/constants.dart';
import 'scan_page.dart';
import 'edit_page.dart';
import 'quote_history_page.dart';

class QuotePage extends StatefulWidget {
  const QuotePage({super.key});

  @override
  State<QuotePage> createState() => _QuotePageState();
}

class _QuotePageState extends State<QuotePage> {
  late QuoteProvider _quoteProvider;
  bool _inited = false;

  /// 连续扫码时扫到、但本地库没有的条码（退出扫码后提示是否补录）
  List<String> _pendingNewBarcodes = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _quoteProvider = context.read<QuoteProvider>();
    if (!_inited) {
      _inited = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _quoteProvider.loadOrCreateDraft();
      });
    }
  }

  @override
  void dispose() {
    // 页面退出前立即落库（fire and forget）
    _quoteProvider.flushNow();
    super.dispose();
  }

  // ============ 连续扫码添加 ============
  // 扫码界面不关闭，可连续扫多件；扫到本地库没有的商品只做顶部提示，不弹窗不阻断
  Future<void> _scanAndAdd() async {
    final productProvider = context.read<ProductProvider>();
    final quoteProvider = context.read<QuoteProvider>();

    final notFound = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => ScanPage(
          mode: ScanMode.continuous,
          initialCount: quoteProvider.itemCount,
          onScanned: (barcode) =>
              _handleScannedBarcode(barcode, productProvider, quoteProvider),
        ),
      ),
    );

    if (!mounted || notFound == null || notFound.isEmpty) return;
    setState(() => _pendingNewBarcodes = notFound);
  }

  /// 未建档提示条：不打断扫描，扫完后一次性补录
  Widget _buildPendingBar() {
    final codes = _pendingNewBarcodes;
    return Material(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: Colors.orange.shade800),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '有 ${codes.length} 个商品未建档：${codes.join("、")}',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: _addPendingProducts,
              child: const Text('去添加'),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: '忽略',
              onPressed: () => setState(() => _pendingNewBarcodes = []),
            ),
          ],
        ),
      ),
    );
  }

  /// 逐个建档：已建档的直接加入，未建档的进编辑页，保存后自动加入报价单
  Future<void> _addPendingProducts() async {
    final codes = List<String>.from(_pendingNewBarcodes);
    final productProvider = context.read<ProductProvider>();
    final quoteProvider = context.read<QuoteProvider>();

    for (final barcode in codes) {
      if (!mounted) return;

      var product = await productProvider.getProductByBarcode(barcode);
      if (!mounted) return;

      if (product == null) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => EditPage(initialBarcode: barcode)),
        );
        if (!mounted) return;
        product = await productProvider.getProductByBarcode(barcode);
        if (!mounted) return;
      }

      if (product != null) {
        await quoteProvider.addProduct(product);
        if (!mounted) return;
        setState(() => _pendingNewBarcodes.remove(barcode));
      }
    }

    if (!mounted) return;
    if (_pendingNewBarcodes.isEmpty) AppToast.info('已全部建档并加入报价单');
  }

  /// 连续扫码的单次处理：返回顶部芯片要显示的反馈
  Future<ScanFeedback> _handleScannedBarcode(
    String barcode,
    ProductProvider productProvider,
    QuoteProvider quoteProvider,
  ) async {
    final product = await productProvider.getProductByBarcode(barcode);

    // 本地库没有：顶部提示 2 秒消失，不弹窗、不阻断，继续扫下一件
    if (product == null) {
      return ScanFeedback(
        message: '未找到：$barcode',
        totalCount: quoteProvider.itemCount,
        notFound: true,
      );
    }

    final existed = quoteProvider.items.any((it) => it.barcode == barcode);

    // 明细上限保护（同一商品累加数量不受限）
    if (!existed && quoteProvider.items.length >= AppConstants.quoteMaxItems) {
      return ScanFeedback(
        message: '单笔报价单最多 ${AppConstants.quoteMaxItems} 项',
        totalCount: quoteProvider.itemCount,
      );
    }

    await quoteProvider.addProduct(product);
    return ScanFeedback(
      message: existed ? '数量 +1：${product.name}' : '已添加：${product.name}',
      totalCount: quoteProvider.itemCount,
    );
  }

  // ============ 保存 ============
  Future<void> _save() async {
    final provider = context.read<QuoteProvider>();
    final err = await provider.saveAsOfficial();
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('报价单已保存')));
    Navigator.pop(context);
  }

  // ============ 清空当前单 ============
  Future<void> _clearCurrent() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空当前单'),
        content: const Text('将清空报价单的所有商品，不可撤销。确认吗？'),
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
    if (confirm != true || !mounted) return;
    await context.read<QuoteProvider>().clearCurrentDraft();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已清空')));
    }
  }

  // ============ 编辑文本（重命名/客户/备注） ============
  Future<void> _editTextField({
    required String title,
    required String? initial,
    required ValueChanged<String?> onSave,
  }) async {
    final ctrl = TextEditingController(text: initial ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null) onSave(result.isEmpty ? null : result);
  }

  // ============ 修改数量 ============
  Future<void> _editQuantity(int index, int current) async {
    final ctrl = TextEditingController(text: current.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改数量'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '1 ~ 9999',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text);
              Navigator.pop(ctx, v);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != null && result > 0 && mounted) {
      context.read<QuoteProvider>().setQuantity(index, result);
    }
  }

  // ============ 减少数量 ============
  Future<void> _decrement(int index) async {
    final provider = context.read<QuoteProvider>();
    final item = provider.items[index];
    if (item.quantity > 1) {
      provider.decrement(index);
    } else {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('移除商品'),
          content: Text('「${item.name}」数量已为 1，是否移除？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('移除', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (confirm == true) provider.removeAt(index);
    }
  }

  // ============ 手动搜索添加 ============
  Future<void> _searchAndAdd() async {
    final quoteProvider = context.read<QuoteProvider>();
    final productProvider = context.read<ProductProvider>();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ProductPickerSheet(
        quoteProvider: quoteProvider,
        productProvider: productProvider,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<QuoteProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(provider.draft?.name ?? '报价单'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'history':
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const QuoteHistoryPage()),
                  );
                  break;
                case 'rename':
                  await _editTextField(
                    title: '重命名',
                    initial: provider.draft?.name,
                    onSave: (v) => provider.setName(v),
                  );
                  break;
                case 'customer':
                  await _editTextField(
                    title: '客户名',
                    initial: provider.draft?.customer,
                    onSave: (v) => provider.setCustomer(v),
                  );
                  break;
                case 'note':
                  await _editTextField(
                    title: '备注',
                    initial: provider.draft?.note,
                    onSave: (v) => provider.setNote(v),
                  );
                  break;
                case 'clear':
                  await _clearCurrent();
                  break;
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'history', child: Text('📜 历史报价单')),
              PopupMenuItem(value: 'rename', child: Text('重命名')),
              PopupMenuItem(value: 'customer', child: Text('客户名')),
              PopupMenuItem(value: 'note', child: Text('备注')),
              PopupMenuItem(value: 'clear', child: Text('清空当前单')),
            ],
          ),
          TextButton(
            onPressed: provider.isSaving ? null : _save,
            child: provider.isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_pendingNewBarcodes.isNotEmpty) _buildPendingBar(),
                Expanded(child: _buildItemList(provider)),
                _buildBottomBar(provider),
              ],
            ),
    );
  }

  // ============ 明细列表 ============
  Widget _buildItemList(QuoteProvider provider) {
    if (provider.items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 8),
            Text('报价单为空', style: TextStyle(color: Colors.grey)),
            SizedBox(height: 4),
            Text(
              '点击下方按钮扫码或手动添加',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: provider.items.length,
      itemBuilder: (ctx, i) {
        final item = provider.items[i];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: '移除',
                      onPressed: () => provider.removeAt(i),
                    ),
                  ],
                ),
                if (item.spec != null && item.spec!.isNotEmpty)
                  Text(
                    '规格：${item.spec}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '¥${item.unitPrice.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => _decrement(i),
                    ),
                    GestureDetector(
                      onTap: () => _editQuantity(i, item.quantity),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${item.quantity}',
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => provider.increment(i),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '¥${item.subtotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============ 底部 ============
  Widget _buildBottomBar(QuoteProvider provider) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  '共 ${provider.itemCount} 件',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const Spacer(),
                const Text('总价：', style: TextStyle(fontSize: 15)),
                Text(
                  '¥${provider.totalPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('扫码添加'),
                    onPressed: _scanAndAdd,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.search),
                    label: const Text('手动搜索'),
                    onPressed: _searchAndAdd,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============ 商品选择弹窗（独立 StatefulWidget） ============
class _ProductPickerSheet extends StatefulWidget {
  final QuoteProvider quoteProvider;
  final ProductProvider productProvider;

  const _ProductPickerSheet({
    required this.quoteProvider,
    required this.productProvider,
  });

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Product> _results = [];

  @override
  void initState() {
    super.initState();
    _results = List.from(widget.productProvider.allProducts);
    widget.quoteProvider.addListener(_onQuoteChanged);
  }

  void _onQuoteChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.quoteProvider.removeListener(_onQuoteChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _doSearch(String kw) {
    final all = widget.productProvider.allProducts;
    final list = kw.trim().isEmpty
        ? all
        : all.where((p) {
            final k = kw.toLowerCase();
            return p.name.toLowerCase().contains(k) ||
                p.barcode.toLowerCase().contains(k) ||
                (p.brand ?? '').toLowerCase().contains(k) ||
                (p.spec ?? '').toLowerCase().contains(k);
          }).toList();
    setState(() => _results = list);
  }

  @override
  Widget build(BuildContext context) {
    final quoteProvider = widget.quoteProvider;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, scrollCtrl) {
        return Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                '选择商品',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  hintText: '🔍 搜名称、条码、品牌、规格',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: _doSearch,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _results.isEmpty
                  ? const Center(child: Text('无匹配商品'))
                  : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: _results.length,
                      itemBuilder: (_, i) {
                        final p = _results[i];
                        final cartIdx = quoteProvider.items.indexWhere(
                          (it) => it.barcode == p.barcode,
                        );
                        final inCart = cartIdx >= 0;
                        final qty = inCart
                            ? quoteProvider.items[cartIdx].quantity
                            : 0;
                        return ListTile(
                          title: Text(p.name),
                          subtitle: Text(
                            '${p.barcode}${p.spec?.isNotEmpty == true ? " · ${p.spec}" : ""}',
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '¥${p.sellingPrice.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (inCart)
                                Text(
                                  '已加入($qty)',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.green,
                                  ),
                                ),
                            ],
                          ),
                          onTap: () async {
                            await quoteProvider.addProduct(p);
                            // 监听器会触发 setState 刷新
                          },
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
