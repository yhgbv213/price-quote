// lib/pages/home_page.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../providers/product_provider.dart';
import '../providers/quote_provider.dart';
import '../services/export_service.dart';
import '../services/image_service.dart';
import '../widgets/app_bar_icon_button.dart';
import 'edit_page.dart';
import 'recycle_page.dart';
import 'scan_page.dart';
import 'quote_page.dart';

import 'settings_page.dart';

import '../providers/settings_provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ============ 底部操作栏 ============
  /// 底栏高度：48dp 触控区（内含 40dp 圆形按钮）+ 上下各 4dp（不含系统安全区）
  static const double _actionBarHeight = 56;

  /// 列表底部留白：底栏已不遮挡内容，只留一点呼吸空间
  static const double _listBottomInset = 12;

  final TextEditingController _searchController = TextEditingController();
  final ImageService _imageService = ImageService();

  @override
  void initState() {
    super.initState();
    // 首次打开检查是否弹免费模式提示
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFreeModeTip();
    });
  }

  // ============ 检查并弹出免费模式提示 ============
  Future<void> _checkFreeModeTip() async {
    if (!mounted) return;

    // 等 SettingsProvider 加载完成（最多等 1 秒）
    int tries = 0;
    while (!context.read<SettingsProvider>().loaded && tries < 10) {
      await Future.delayed(const Duration(milliseconds: 100));
      tries++;
      if (!mounted) return;
    }
    if (!mounted) return;

    final settings = context.read<SettingsProvider>();
    if (settings.freeModeTipShown) return; // 已读过

    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.cloud_done,
                      color: Colors.green.shade600,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '当前查询模式：免费模式',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                '正在使用 Open Food Facts 免费数据源（无需注册）。',
                style: TextStyle(fontSize: 14, height: 1.6),
              ),
              const SizedBox(height: 8),
              const Text(
                '💡 如需查询国内商品（如 69 开头条码），推荐在「设置 → 查询数据源」中启用「极数本源」源（需自行订阅）。',
                style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.6),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await settings.markFreeModeTipShown();
                        if (!mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SettingsPage(),
                          ),
                        );
                      },
                      child: const Text('去设置'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await settings.markFreeModeTipShown();
                      },
                      child: const Text('我知道了'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ============ 导出 Excel ============
  Future<void> _exportExcel() async {
    final provider = context.read<ProductProvider>();
    final messenger = ScaffoldMessenger.of(context); // ← 提前取
    final all = provider.allProducts;
    if (all.isEmpty) {
      _snack('暂无数据，请先添加商品');
      return;
    }
    try {
      await ExportService().exportProducts(all);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导出失败: $e')));
    }
  }

  // ============ 进回收站 ============
  Future<void> _goRecycle() async {
    final provider = context.read<ProductProvider>(); // ← 提前取
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecyclePage()),
    );
    if (mounted) provider.refreshRecycleCount(); // ← 用局部变量
  }

  // ============ 进报价单 ============
  Future<void> _goQuote() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QuotePage()),
    );
    if (mounted) setState(() {});
  }

  // ============ 首页扫码（查价） ============
  Future<void> _scanForPrice() async {
    final productProvider = context.read<ProductProvider>(); // ← 提前取
    final barcode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanPage()),
    );
    if (!mounted || barcode == null || barcode.isEmpty) return;

    final product = await productProvider.getProductByBarcode(barcode);
    if (!mounted) return;

    if (product == null) {
      final add = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('未找到商品'),
          content: Text('条码 $barcode 不在本地库中，是否立即添加？'),
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
      if (add == true && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => EditPage(initialBarcode: barcode)),
        );
      }
      return;
    }

    if (!mounted) return;
    _showPricePopup(product.name, product.sellingPrice, product.spec);
  }

  // ============ 售价浮窗（2秒自动关） ============
  void _showPricePopup(String name, double price, String? spec) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        Future.delayed(const Duration(seconds: 2), () {
          if (Navigator.canPop(ctx)) Navigator.pop(ctx);
        });
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (spec != null && spec.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      spec,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  '¥${price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.yellowAccent,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============ 新增商品 ============
  Future<void> _addProduct() async {
    final provider = context.read<ProductProvider>();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EditPage()),
    );
    if (mounted) provider.loadProducts();
  }

  // ============ 编辑商品 ============
  Future<void> _editProduct(Product p) async {
    final provider = context.read<ProductProvider>(); // ← 提前取
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditPage(product: p)),
    );
    if (mounted) provider.loadProducts(); // ← 用局部变量
  }

  // ============ 左滑移入回收站 ============
  Future<void> _deleteProduct(Product p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移入回收站'),
        content: Text('「${p.name}」将被移入回收站，30 天内可恢复。'),
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
    if (confirm == true && mounted) {
      await context.read<ProductProvider>().moveToRecycleBin(p);
      if (mounted) _snack('已移至回收站');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ============ AppBar ============
      appBar: AppBar(
        title: const Text('商品报价'),
        actions: [
          // ⋮ 更多菜单
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'export':
                  await _exportExcel();
                  break;
                case 'batch':
                  _snack('批量编辑开发中...');
                  break;
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'export', child: Text('📥 导出 Excel')),
              PopupMenuItem(value: 'batch', child: Text('📝 批量编辑')),
            ],
          ),
          // 回收站（带角标）
          Consumer<ProductProvider>(
            builder: (ctx, provider, _) => AppBarIconButton(
              icon: Icons.delete_outline,
              tooltip: '回收站',
              badgeCount: provider.recycleCount,
              onPressed: _goRecycle,
            ),
          ),
          // 设置
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
          ),
        ],
      ),
      // ============ 主体 ============
      body: Column(
        children: [
          _buildSearchBox(),
          _buildCategoryChips(),
          const Divider(height: 1),
          Expanded(child: _buildProductList()),
        ],
      ),
      // ============ 底部操作栏（常驻，不悬浮） ============
      // 列表在底栏上方结束，因此任何内容量都不会被遮挡
      bottomNavigationBar: _buildActionBar(),
    );
  }

  // ============ 底部操作栏 ============
  Widget _buildActionBar() {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      elevation: 8,
      // 深色模式下阴影几乎不可见，补一条顶部分隔线区分底栏与内容
      shape: Border(
        top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _actionBarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                // 左侧：常驻数据概览（受「显示数据概览」开关控制）
                Expanded(child: _buildBarDashboard()),
                _actionButton(
                  icon: Icons.qr_code_scanner,
                  tooltip: '扫码查价',
                  onPressed: _scanForPrice,
                ),
                const SizedBox(width: 4),
                _actionButton(
                  icon: Icons.add,
                  tooltip: '新增商品',
                  onPressed: _addProduct,
                ),
                const SizedBox(width: 4),
                Consumer<QuoteProvider>(
                  builder: (ctx, quoteProvider, _) => _actionButton(
                    icon: Icons.shopping_cart,
                    tooltip: '报价单',
                    badgeCount: quoteProvider.itemCount,
                    onPressed: _goQuote,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 底栏动作按钮：圆形点击区 + 可选数量角标
  ///
  /// 配色按 WCAG 2.1 选取（非文本图形 ≥ 3:1，文本 ≥ 4.5:1）：
  /// - **深色**：亮蓝实心底 #90CAF9 + 深蓝图标 #0D47A1
  ///   底 vs 背景 **11.0:1**，图标 vs 底 **4.9:1**
  /// - **浅色**：淡蓝实心底 #E3F2FD + 蓝图标 #1976D2
  ///   图标 vs 底 **3.9:1**
  ///
  /// 注意：不用「半透明底」——26% 的主色叠在深背景上只有 1.9:1，
  /// 形状会糊进背景里，这正是旧版深色下看不清的原因。
  Widget _actionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    int badgeCount = 0,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final circleColor = isDark ? Colors.blue.shade200 : Colors.blue.shade50;
    final iconColor = isDark ? Colors.blue.shade900 : Colors.blue.shade700;

    Widget iconWidget = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: circleColor, shape: BoxShape.circle),
      child: Icon(icon, size: 20, color: iconColor),
    );

    if (badgeCount > 0) {
      iconWidget = Badge.count(
        count: badgeCount,
        maxCount: 99,
        backgroundColor: Colors.red,
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
        child: iconWidget,
      );
    }

    return IconButton(
      icon: iconWidget,
      tooltip: tooltip,
      onPressed: onPressed,
      // 去掉默认 8dp 内边距，仅保留 48dp 最小触控区（Material 无障碍下限）
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    );
  }

  // ============ 数据概览（底栏左侧，常驻可见） ============
  // 统计口径：当前筛选 / 搜索结果的数量与总价（规格 2B.2）
  Widget _buildBarDashboard() {
    final settings = context.watch<SettingsProvider>();
    if (!settings.showDashboard) return const SizedBox.shrink();

    final provider = context.watch<ProductProvider>();

    // 底栏空间有限：这里只放两个关键数字，点开看明细
    return InkWell(
      onTap: () => _showDashboardDetail(provider),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '共 ${provider.totalCount} 件',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 2),
            Text(
              '¥${provider.totalValue.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ============ 概览详情弹窗 ============
  Future<void> _showDashboardDetail(ProductProvider provider) async {
    final all = provider.allProducts;
    final allValue = all.fold<double>(0, (sum, p) => sum + p.sellingPrice);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('数据概览'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow(
                '当前筛选',
                '${provider.totalCount} 件',
                '¥${provider.totalValue.toStringAsFixed(2)}',
                highlight: true,
              ),
              const Divider(height: 16),
              _detailRow(
                '全部商品',
                '${all.length} 件',
                '¥${allValue.toStringAsFixed(2)}',
              ),
              const Divider(height: 16),
              _detailRow('回收站', '${provider.recycleCount} 件', null),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 详情弹窗的一行：标签 + 件数 + 金额
  Widget _detailRow(
    String label,
    String count,
    String? value, {
    bool highlight = false,
  }) {
    final style = TextStyle(
      fontSize: 14,
      fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(
            count,
            style: TextStyle(
              fontSize: 13,
              color: highlight ? null : Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 96,
            child: Text(value ?? '—', textAlign: TextAlign.right, style: style),
          ),
        ],
      ),
    );
  }

  // ============ 排序菜单 ============
  void _showSortMenu() {
    final provider = context.read<ProductProvider>();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  '排序方式',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              ...ProductProvider.sortFields.map((opt) {
                final field = opt['field']!;
                final label = opt['label']!;
                final isActive = provider.sortField == field;
                return ListTile(
                  title: Text(label),
                  trailing: isActive
                      ? Icon(
                          provider.sortDesc
                              ? Icons.arrow_downward
                              : Icons.arrow_upward,
                          color: Colors.blue,
                          size: 20,
                        )
                      : null,
                  selected: isActive,
                  selectedTileColor: Colors.blue.withValues(alpha: 0.08),
                  onTap: () async {
                    await provider.toggleSort(field);
                    setModalState(() {}); // ← 关键：手动刷新弹窗
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ============ 搜索框 ============
  Widget _buildSearchBox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: '🔍 搜名称、条码、品牌、规格（支持跳码）',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_searchController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  tooltip: '清空',
                  onPressed: () {
                    _searchController.clear();
                    context.read<ProductProvider>().setSearchKeyword('');
                    setState(() {});
                  },
                ),
              // 排序按钮
              IconButton(
                icon: const Icon(Icons.sort),
                tooltip: '排序',
                onPressed: _showSortMenu,
              ),
            ],
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          isDense: true,
        ),
        onChanged: (value) {
          context.read<ProductProvider>().setSearchKeyword(value);
          setState(() {});
        },
      ),
    );
  }

  // ============ 分类芯片 ============
  Widget _buildCategoryChips() {
    final provider = context.watch<ProductProvider>();
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: ProductProvider.presetCategories.length,
        itemBuilder: (ctx, i) {
          final cat = ProductProvider.presetCategories[i];
          final isSelected = cat == provider.selectedCategory;
          return Padding(
            padding: const EdgeInsets.only(right: 6, top: 4, bottom: 4),
            child: ChoiceChip(
              label: Text(cat),
              selected: isSelected,
              onSelected: (_) => provider.setCategory(cat),
            ),
          );
        },
      ),
    );
  }

  // ============ 商品头像（有图显示缩略图，无图显示首字） ============
  Widget _buildProductAvatar(Product p) {
    if (p.localImagePath == null || p.localImagePath!.isEmpty) {
      return _defaultAvatar(p);
    }

    return FutureBuilder<File?>(
      future: _imageService.resolveFile(p.localImagePath),
      builder: (ctx, snap) {
        // 加载中：先显示首字头像（避免闪白）
        if (snap.connectionState != ConnectionState.done) {
          return _defaultAvatar(p);
        }
        final file = snap.data;
        if (file == null || !file.existsSync()) {
          return _defaultAvatar(p);
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Image.file(
            file,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _defaultAvatar(p),
          ),
        );
      },
    );
  }

  // 默认首字头像
  Widget _defaultAvatar(Product p) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return CircleAvatar(
      backgroundColor: isDark ? Colors.blue.shade900 : Colors.blue.shade100,
      child: Text(
        p.name.isNotEmpty ? p.name.characters.first : '?',
        style: TextStyle(
          color: isDark ? Colors.blue.shade200 : Colors.blue,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 搜索词为纯数字（≥4 位）且命中条码时，标题后追加「条码包含 xxx」标签
  Widget _buildTitleWithBarcodeTag(Product p, ProductProvider provider) {
    final kw = provider.searchKeyword.trim();
    final hit =
        provider.isBarcodeSearch &&
        p.barcode.toLowerCase().contains(kw.toLowerCase());

    if (!hit) return Text(p.name);

    return Row(
      children: [
        Flexible(child: Text(p.name, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Text(
            '条码包含 $kw',
            style: TextStyle(fontSize: 10, color: Colors.blue.shade700),
          ),
        ),
      ],
    );
  }

  // ============ 商品列表 ============
  Widget _buildProductList() {
    final provider = context.watch<ProductProvider>();
    final products = provider.products;

    if (products.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey),
            SizedBox(height: 8),
            Text('暂无商品', style: TextStyle(color: Colors.grey)),
            SizedBox(height: 4),
            Text(
              '点击底部 + 添加商品',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      // 底部留白：底栏已不遮挡内容，只留一点呼吸空间
      padding: const EdgeInsets.only(bottom: _listBottomInset),
      itemCount: products.length,
      itemBuilder: (ctx, i) {
        final p = products[i];
        final categoryText = p.category.isEmpty ? '未分类' : p.category;

        return Dismissible(
          key: ValueKey('product_${p.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          confirmDismiss: (_) async {
            await _deleteProduct(p);
            return false;
          },
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ListTile(
              onTap: () => _editProduct(p),
              leading: _buildProductAvatar(p),
              title: _buildTitleWithBarcodeTag(p, provider),
              subtitle: Text('条码: ${p.barcode}\n分类: $categoryText'),
              isThreeLine: true,
              trailing: Text(
                '¥${p.sellingPrice.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
