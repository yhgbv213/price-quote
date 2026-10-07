// lib/pages/edit_page.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/api_result.dart';
import '../models/product.dart';
import '../providers/product_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import '../services/image_service.dart';
import '../utils/constants.dart';
import '../utils/app_toast.dart';
import 'scan_page.dart';

class EditPage extends StatefulWidget {
  final Product? product;
  final String? initialBarcode;

  const EditPage({super.key, this.product, this.initialBarcode});

  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _brandCtrl;
  late final TextEditingController _specCtrl;
  late final TextEditingController _priceCtrl;

  final FocusNode _barcodeFocus = FocusNode();
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _brandFocus = FocusNode();
  final FocusNode _specFocus = FocusNode();
  final FocusNode _priceFocus = FocusNode();
  final ImageService _imageService = ImageService();

  late String _category;
  bool _categoryManuallyChanged = false;
  bool _saving = false;
  bool _querying = false;
  bool _refreshing = false;
  int _continueCount = 0;
  bool _allowPop = false;
  bool _priceIsPlaceholder = false;
  ApiResult? _lastApiResult; // 最近一次查询结果（用于显示来源）

  String? _originalImagePath;
  String? _currentImagePath;
  File? _pendingImageFile;
  bool _imageDeleted = false;

  /// 最近一次查询的来源文案（用于 helperText 显示）
  // ignore: unused_field
  String? _lastSourceText;

  bool get _isEditing => widget.product != null;

  static const List<String> categoryOptions = [
    '未分类',
    '烟',
    '酒',
    '饮料',
    '零食',
    '日用品',
    '其他',
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _barcodeCtrl = TextEditingController(
      text: p?.barcode ?? widget.initialBarcode ?? '',
    );
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _brandCtrl = TextEditingController(text: p?.brand ?? '');
    _specCtrl = TextEditingController(text: p?.spec ?? '');
    _priceCtrl = TextEditingController(
      text: p != null ? p.sellingPrice.toStringAsFixed(2) : '',
    );
    _category = p?.category.isNotEmpty == true ? p!.category : '未分类';
    _originalImagePath = p?.localImagePath;
    _currentImagePath = p?.localImagePath;

    _barcodeCtrl.addListener(_onAnyFieldChanged);
    _nameCtrl.addListener(_onAnyFieldChanged);
    _brandCtrl.addListener(_onAnyFieldChanged);
    _specCtrl.addListener(_onAnyFieldChanged);
    _priceCtrl.addListener(_onAnyFieldChanged);
  }

  @override
  void dispose() {
    _barcodeCtrl.removeListener(_onAnyFieldChanged);
    _nameCtrl.removeListener(_onAnyFieldChanged);
    _brandCtrl.removeListener(_onAnyFieldChanged);
    _specCtrl.removeListener(_onAnyFieldChanged);
    _priceCtrl.removeListener(_onAnyFieldChanged);

    _barcodeCtrl.dispose();
    _nameCtrl.dispose();
    _brandCtrl.dispose();
    _specCtrl.dispose();
    _priceCtrl.dispose();
    _barcodeFocus.dispose();
    _nameFocus.dispose();
    _brandFocus.dispose();
    _specFocus.dispose();
    _priceFocus.dispose();
    super.dispose();
  }

  void _onNameChanged(String value) {
    if (_categoryManuallyChanged) return;
    final recommended = ProductProvider.recommendCategory(value);
    if (recommended != _category) {
      setState(() => _category = recommended);
    }
  }

  void _onAnyFieldChanged() {
    if (mounted) setState(() {});
  }

  // 条码变化时清空来源（由条码输入框单独绑定）
  void _onBarcodeManualChange() {
    if (_lastApiResult != null) {
      setState(() => _lastApiResult = null);
    }
  }

  // ============ 条码提示文字 ============
  String _barcodeHelperText() {
    if (_isEditing) return '';

    // 如果查询过，优先显示来源
    if (_lastApiResult != null) {
      final r = _lastApiResult!;
      if (r.isFromCache) {
        final age = r.cacheAgeText ?? '刚刚';
        return '📥 缓存·${r.sourceName}，$age';
      } else {
        return '🌐 ${r.sourceName}，${r.elapsedText}';
      }
    }

    // 未查询
    final bc = _barcodeCtrl.text.trim();
    if (bc.isEmpty) {
      return '输入后按回车检测重复，或点右侧按钮联网查询';
    }
    final len = bc.length;
    String hint;
    switch (len) {
      case 8:
        hint = 'EAN-8';
        break;
      case 12:
        hint = 'UPC-A';
        break;
      case 13:
        hint = 'EAN-13';
        break;
      case 14:
        hint = 'ITF-14';
        break;
      default:
        hint = '非常见条码长度';
    }
    return '当前长度：$len 位（$hint）';
  }

  // ============ 来源文案 ============
  // - 缓存：📥 缓存·Open Food Facts，3天前
  // - 网络：🌐 Open Food Facts，1.2s
  String _buildSourceText(ApiResult r) {
    if (r.isFromCache) {
      final age = r.cacheAgeText ?? '刚刚';
      return '📥 缓存·${r.sourceName}，$age';
    }
    return '🌐 ${r.sourceName}，${r.elapsedText}';
  }

  // ============ 条码提示（含强制刷新入口） ============
  /// 查询前是纯文案；拿到过查询结果后，追加可点击的「🔄 强制刷新」
  Widget? _buildBarcodeHelper() {
    if (_isEditing) return null;

    final text = _barcodeHelperText();
    if (text.isEmpty) return null;

    final baseStyle = TextStyle(
      fontSize: 12,
      color: Theme.of(context).hintColor,
    );

    // 只有查询过才提供刷新入口
    if (_lastApiResult == null) return Text(text, style: baseStyle);

    return Row(
      children: [
        Flexible(
          child: Text(
            text,
            style: baseStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 6),
        InkWell(
          onTap: _refreshing ? null : _forceRefresh,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
            child: Text(
              _refreshing ? '刷新中…' : '🔄 强制刷新',
              style: baseStyle.copyWith(
                color: _refreshing
                    ? Theme.of(context).disabledColor
                    : Theme.of(context).primaryColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 清空按钮：清空后自动聚焦该输入框，省一步点击
  Widget? _clearIcon(TextEditingController ctrl, FocusNode focus) {
    if (ctrl.text.isEmpty) return null;
    return IconButton(
      icon: const Icon(Icons.clear, size: 20),
      tooltip: '清空',
      onPressed: () {
        ctrl.clear();
        focus.requestFocus();
        setState(() {});
      },
    );
  }

  // ============ 是否有未保存改动 ============
  bool get _hasUnsavedChanges {
    if (_pendingImageFile != null || _imageDeleted) return true;

    if (!_isEditing) {
      return _barcodeCtrl.text.trim().isNotEmpty ||
          _nameCtrl.text.trim().isNotEmpty ||
          _brandCtrl.text.trim().isNotEmpty ||
          _specCtrl.text.trim().isNotEmpty ||
          (!_priceIsPlaceholder && _priceCtrl.text.trim().isNotEmpty);
    }

    final p = widget.product!;
    if (_barcodeCtrl.text.trim() != p.barcode) return true;
    if (_nameCtrl.text.trim() != p.name) return true;
    if (_brandCtrl.text.trim() != (p.brand ?? '')) return true;
    if (_specCtrl.text.trim() != (p.spec ?? '')) return true;
    if (_priceCtrl.text.trim() != p.sellingPrice.toStringAsFixed(2)) {
      return true;
    }
    final origCategory = p.category.isNotEmpty ? p.category : '未分类';
    if (_category != origCategory) return true;
    return false;
  }

  Future<bool> _confirmExit() async {
    if (!_hasUnsavedChanges) return true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('未保存'),
        content: const Text('有未保存的内容，是否放弃？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('放弃', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  // ============ 表单重置 ============
  bool get _hasAnyInput {
    return _barcodeCtrl.text.isNotEmpty ||
        _nameCtrl.text.isNotEmpty ||
        _brandCtrl.text.isNotEmpty ||
        _specCtrl.text.isNotEmpty ||
        _priceCtrl.text.isNotEmpty ||
        _pendingImageFile != null;
  }

  Future<void> _confirmResetForm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空表单'),
        content: const Text('将清空当前录入的所有内容，确认吗？'),
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
    if (confirmed != true || !mounted) return;

    setState(() {
      _barcodeCtrl.clear();
      _nameCtrl.clear();
      _brandCtrl.clear();
      _specCtrl.clear();
      _priceCtrl.clear();
      _category = '未分类';
      _categoryManuallyChanged = false;
      _continueCount = 0;
      _pendingImageFile = null;
      _priceIsPlaceholder = false;
      _lastSourceText = null;
      if (_isEditing) {
        _currentImagePath = _originalImagePath;
        _imageDeleted = false;
      } else {
        _currentImagePath = null;
      }
    });
    _toast('表单已清空');
  }

  // ============ 图片 ============
  Future<void> _pickImage() async {
    final hasImage =
        _pendingImageFile != null || (_currentImagePath?.isNotEmpty == true);

    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
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
                '商品图片',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            if (hasImage)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('删除图片', style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted || choice == null) return;

    if (choice == 'delete') {
      setState(() {
        _pendingImageFile = null;
        _currentImagePath = null;
        _imageDeleted = true;
      });
      _toast('图片已删除');
      return;
    }

    try {
      File? picked;
      if (choice == 'gallery') {
        picked = await _imageService.pickFromGallery();
      } else {
        picked = await _imageService.pickFromCamera();
      }
      if (picked == null || !mounted) return;

      setState(() {
        _pendingImageFile = picked;
        _imageDeleted = false;
      });
      _toast('已选择图片，保存后生效');
    } catch (e) {
      if (mounted) _toast('选择图片失败: $e');
    }
  }

  Widget _buildImageSection() {
    Widget content;
    if (_pendingImageFile != null) {
      content = Image.file(_pendingImageFile!, fit: BoxFit.cover);
    } else if (_currentImagePath != null && _currentImagePath!.isNotEmpty) {
      content = FutureBuilder<File?>(
        future: _imageService.resolveFile(_currentImagePath),
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final f = snap.data;
          if (f == null || !f.existsSync()) return _placeholderIcon();
          return Image.file(f, fit: BoxFit.cover);
        },
      );
    } else {
      content = _placeholderIcon();
    }

    return Center(
      child: GestureDetector(
        onTap: _pickImage,
        child: Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey.shade900
                : Colors.grey.shade50,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(child: content),
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.photo_camera,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholderIcon() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.image_outlined, size: 40, color: Colors.grey.shade400),
        const SizedBox(height: 6),
        Text(
          '点击添加图片',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  // ============ 上次价 ============
  Future<void> _fillLastPrice() async {
    final barcode = _barcodeCtrl.text.trim();
    if (barcode.isEmpty) {
      _toast('请先输入条码');
      return;
    }
    final price = await context.read<ProductProvider>().getLastPrice(barcode);
    if (!mounted) return;
    if (price == null) {
      _toast('该条码暂无历史价格');
      return;
    }
    _priceCtrl.text = price.toStringAsFixed(2);
    setState(() => _priceIsPlaceholder = false);
  }

  // ============ 扫码 ============
  Future<void> _scanBarcode() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanPage()),
    );
    if (!mounted || code == null || code.isEmpty) return;

    setState(() {
      _barcodeCtrl.text = code;
      _lastSourceText = null; // 换条码清空来源
    });
    await _checkBarcodeConflict();
  }

  // ============ 联网查询 ============
  Future<void> _queryFromApi({bool force = false}) async {
    final barcode = _barcodeCtrl.text.trim();
    if (barcode.isEmpty) {
      _toast('请先输入条码');
      return;
    }
    if (barcode.startsWith(AppConstants.autoBarcodePrefix)) {
      _toast('AUTO_ 序号不支持联网查询');
      return;
    }

    setState(() => _querying = true);
    try {
      final result = await ApiService().query(barcode, forceRefresh: force);
      if (!mounted) return;

      if (!result.success) {
        _toast(result.errorMessage ?? '查询失败');
        return;
      }

      final sourceText = _buildSourceText(result);

      setState(() {
        _lastApiResult = result; // ← 新增
        if (result.name != null && result.name!.isNotEmpty) {
          _nameCtrl.text = result.name!;
        }
        if (result.brand != null && result.brand!.isNotEmpty) {
          _brandCtrl.text = result.brand!;
        }
        if (result.spec != null && result.spec!.isNotEmpty) {
          _specCtrl.text = result.spec!;
        }
        if (!_categoryManuallyChanged && _nameCtrl.text.isNotEmpty) {
          _category = ProductProvider.recommendCategory(_nameCtrl.text);
        }
        _lastSourceText = sourceText;
      });

      if (!result.nameIsChinese) {
        _toast('商品名为非中文，可手动修改（$sourceText）');
      } else {
        _toast('已填充（$sourceText）');
      }
    } catch (e) {
      if (!mounted) return;
      _toast('查询出错: $e');
    } finally {
      if (mounted) setState(() => _querying = false);
    }
  }

  // ============ 单条强制刷新 ============
  /// 跳过缓存直接联网；失败时保留原缓存（由 ApiService 保证）
  Future<void> _forceRefresh() async {
    if (_querying || _refreshing) return;
    final barcode = _barcodeCtrl.text.trim();
    if (barcode.isEmpty || barcode.startsWith(AppConstants.autoBarcodePrefix)) {
      return;
    }

    setState(() => _refreshing = true);
    try {
      // 超时保护：8 秒仍未结束就恢复按钮，避免卡在"刷新中…"
      await _queryFromApi(force: true).timeout(const Duration(seconds: 8));
    } catch (_) {
      // 失败原因已由 _queryFromApi 提示，这里只负责恢复按钮状态
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  // ============ 重复条码检查 ============
  Future<bool> _checkBarcodeConflict() async {
    final barcode = _barcodeCtrl.text.trim();
    if (barcode.isEmpty || barcode.startsWith(AppConstants.autoBarcodePrefix)) {
      return false;
    }

    final existing = await context.read<ProductProvider>().getProductByBarcode(
      barcode,
    );
    if (existing == null) return false;

    if (!mounted) return true;
    await _showBarcodeConflictSheet(existing);
    return true;
  }

  Future<void> _showBarcodeConflictSheet(Product existing) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
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
                '该条码已存在',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text('编辑此商品'),
              subtitle: Text(existing.name),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: Colors.orange),
              title: const Text('复制并新建'),
              subtitle: const Text('复制该商品信息，清空条码'),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted || choice == null) return;

    if (choice == 'edit') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => EditPage(product: existing)),
      );
    } else if (choice == 'copy') {
      _barcodeCtrl.text = '';
      setState(() {
        _nameCtrl.text = existing.name;
        _brandCtrl.text = existing.brand ?? '';
        _specCtrl.text = existing.spec ?? '';
        _priceCtrl.text = existing.sellingPrice.toStringAsFixed(2);
        _category = existing.category.isNotEmpty ? existing.category : '未分类';
        _categoryManuallyChanged = true;
        _lastSourceText = null;
        if (existing.localImagePath != null &&
            existing.localImagePath!.isNotEmpty) {
          _currentImagePath = existing.localImagePath;
          _pendingImageFile = null;
          _imageDeleted = false;
        }
      });
      _toast('已复制商品信息，可修改后保存');
    }
  }

  // ============ 校验 ============
  double? _validate() {
    final name = _nameCtrl.text.trim();
    final priceText = _priceCtrl.text.trim();

    if (name.isEmpty) {
      _toast('请填写商品名称');
      return null;
    }
    if (priceText.isEmpty) {
      _toast('请填写售价');
      return null;
    }
    final price = double.tryParse(priceText);
    if (price == null || price <= 0) {
      _toast('售价必须大于 0');
      return null;
    }
    return price;
  }

  // ============ 保存 ============
  Future<void> _save() async {
    if (_saving) return;

    // 清零时机：点「保存」（不带继续）后计数归零
    if (_continueCount != 0) setState(() => _continueCount = 0);

    final price = _validate();
    if (price == null) return;

    if (!_isEditing) {
      setState(() => _saving = true);
      final hasConflict = await _checkBarcodeConflict();
      if (!mounted) return;
      setState(() => _saving = false);
      if (hasConflict) return;
    }

    setState(() => _saving = true);
    try {
      final provider = context.read<ProductProvider>();

      if (_isEditing) {
        final base = widget.product!.copyWith(
          barcode: _barcodeCtrl.text.trim(),
          name: _nameCtrl.text.trim(),
          brand: _brandCtrl.text.trim().isEmpty ? null : _brandCtrl.text.trim(),
          spec: _specCtrl.text.trim().isEmpty ? null : _specCtrl.text.trim(),
          category: _category,
          sellingPrice: price,
        );
        await provider.updateProduct(
          base,
          pendingImageFile: _pendingImageFile,
          deleteImage: _imageDeleted,
        );
        if (!mounted) return;
        _toast('已保存');
        setState(() => _allowPop = true);
        Navigator.pop(context);
      } else {
        final finalBarcode = await provider.saveNewProduct(
          barcode: _barcodeCtrl.text.trim(),
          name: _nameCtrl.text.trim(),
          brand: _brandCtrl.text.trim().isEmpty ? null : _brandCtrl.text.trim(),
          spec: _specCtrl.text.trim().isEmpty ? null : _specCtrl.text.trim(),
          category: _category,
          sellingPrice: price,
          pendingImageFile: _pendingImageFile,
        );
        if (!mounted) return;
        if (_barcodeCtrl.text.trim().isEmpty) {
          _toast('未输入条码，已自动分配 $finalBarcode');
        } else {
          _toast('保存成功');
        }
        setState(() => _allowPop = true);
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ============ 保存并继续 ============
  Future<void> _saveAndContinue() async {
    if (_saving) return;
    if (_isEditing) {
      await _save();
      return;
    }

    final price = _validate();
    if (price == null) return;

    setState(() => _saving = true);
    final hasConflict = await _checkBarcodeConflict();
    if (!mounted) return;
    setState(() => _saving = false);
    if (hasConflict) return;

    setState(() => _saving = true);
    try {
      final provider = context.read<ProductProvider>();
      final finalBarcode = await provider.saveNewProduct(
        barcode: _barcodeCtrl.text.trim(),
        name: _nameCtrl.text.trim(),
        brand: _brandCtrl.text.trim().isEmpty ? null : _brandCtrl.text.trim(),
        spec: _specCtrl.text.trim().isEmpty ? null : _specCtrl.text.trim(),
        category: _category,
        sellingPrice: price,
        pendingImageFile: _pendingImageFile,
      );

      if (!mounted) return;

      _continueCount++;

      setState(() {
        _barcodeCtrl.clear();
        _nameCtrl.clear();
        _brandCtrl.clear();
        _specCtrl.clear();
        _priceCtrl.text = price.toStringAsFixed(2);
        _category = '未分类';
        _categoryManuallyChanged = false;
        _pendingImageFile = null;
        _currentImagePath = null;
        _imageDeleted = false;
        _priceIsPlaceholder = true;
        _lastSourceText = null;
      });

      await _handleImageReuseAfterSave(finalBarcode);
      if (!mounted) return;

      // 录入偏好：开启「自动扫码」时，保存并继续后直接进入扫码
      if (context.read<SettingsProvider>().autoScanAfterSaveContinue) {
        await _scanBarcode();
        if (!mounted) return;
      }

      _nameFocus.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    } catch (e) {
      if (!mounted) return;
      _toast('保存失败: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ============ 图片沿用 ============
  Future<String?> _askImageReuse() async {
    bool remember = false;
    return await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('是否沿用上一张图片？'),
          content: CheckboxListTile(
            value: remember,
            onChanged: (v) => setDialogState(() => remember = v ?? false),
            title: const Text('记住我的选择'),
            subtitle: const Text('下次不再询问，可在设置中修改'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(
                ctx,
                remember ? 'no_reuse_remember' : 'no_reuse',
              ),
              child: const Text('否'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, remember ? 'reuse_remember' : 'reuse'),
              child: const Text('是'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleImageReuseAfterSave(String savedBarcode) async {
    final savedFile = await _imageService.resolveFile(
      'images/$savedBarcode.jpg',
    );
    if (savedFile == null || !savedFile.existsSync()) return;

    if (!mounted) return;
    final settings = context.read<SettingsProvider>();
    final choice = settings.imageReuseChoice;

    if (choice == 'reuse') {
      setState(() => _pendingImageFile = savedFile);
      return;
    }
    if (choice == 'no_reuse') return;

    final result = await _askImageReuse();
    if (!mounted || result == null) return;

    final reuse = result.startsWith('reuse');
    final remember = result.endsWith('_remember');

    if (remember) {
      await settings.setImageReuseChoice(reuse ? 'reuse' : 'no_reuse');
    }

    if (reuse) {
      setState(() => _pendingImageFile = savedFile);
    }
  }

  /// 顶部轻提示（AppBar 下方浮层），不遮挡底部操作按钮。
  void _toast(String msg) {
    AppToast.info(msg);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _confirmExit();
        if (shouldPop && mounted) {
          setState(() => _allowPop = true);
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? '编辑商品' : '新增商品'),
          actions: [
            // 连续操作计数：仅在点过「保存并继续」后显示
            if (_continueCount > 0)
              Center(
                child: Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '已保存 $_continueCount 件',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            if (!_isEditing && _hasAnyInput)
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '清空表单',
                onPressed: _confirmResetForm,
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildImageSection(),
            const SizedBox(height: 16),

            // 条码
            TextField(
              controller: _barcodeCtrl,
              keyboardType: TextInputType.number,
              // readOnly（而非 enabled: false）：编辑时保留长按选中复制能力
              readOnly: _isEditing,
              onChanged: (_) => _onBarcodeManualChange(),
              onSubmitted: (_) async {
                await _checkBarcodeConflict();
              },
              decoration: InputDecoration(
                labelText: '条码',
                hintText: _isEditing ? null : '请输入条码数字（留空自动分配序号）',
                border: const OutlineInputBorder(),
                helper: _buildBarcodeHelper(),
                helperMaxLines: 2,
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_barcodeCtrl.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        tooltip: '清空',
                        onPressed: () {
                          _barcodeCtrl.clear();
                          _barcodeFocus.requestFocus();
                          setState(() {
                            _lastApiResult = null;
                          });
                        },
                      ),
                    if (!_isEditing)
                      IconButton(
                        icon: const Icon(Icons.qr_code_scanner),
                        tooltip: '扫码',
                        onPressed: _scanBarcode,
                      ),
                    _querying
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.cloud_download_outlined),
                            tooltip: '联网查询',
                            onPressed: () => _queryFromApi(),
                          ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 名称
            TextField(
              controller: _nameCtrl,
              focusNode: _nameFocus,
              onChanged: _onNameChanged,
              decoration: InputDecoration(
                labelText: '商品名称 *',
                hintText: '例如：乐事原味薯片',
                border: const OutlineInputBorder(),
                suffixIcon: _clearIcon(_nameCtrl, _nameFocus),
              ),
            ),
            const SizedBox(height: 12),

            // 品牌
            TextField(
              controller: _brandCtrl,
              focusNode: _brandFocus,
              decoration: InputDecoration(
                labelText: '品牌（可选）',
                hintText: '例如：乐事',
                border: const OutlineInputBorder(),
                suffixIcon: _clearIcon(_brandCtrl, _brandFocus),
              ),
            ),
            const SizedBox(height: 12),

            // 规格
            TextField(
              controller: _specCtrl,
              focusNode: _specFocus,
              decoration: InputDecoration(
                labelText: '规格（可选）',
                hintText: '例如：100g',
                border: const OutlineInputBorder(),
                suffixIcon: _clearIcon(_specCtrl, _specFocus),
              ),
            ),
            const SizedBox(height: 12),

            // 分类
            // ignore: deprecated_member_use
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _category,
              decoration: const InputDecoration(
                labelText: '分类',
                border: OutlineInputBorder(),
                helperText: '系统已根据商品名推荐分类，可修改',
              ),
              items: categoryOptions
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _category = v;
                  _categoryManuallyChanged = true;
                });
              },
            ),
            const SizedBox(height: 12),

            // 售价
            TextField(
              controller: _priceCtrl,
              focusNode: _priceFocus,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onTap: () {
                // 用户点击价格框时全选，方便覆盖输入
                _priceCtrl.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: _priceCtrl.text.length,
                );
              },
              onChanged: (_) {
                if (_priceIsPlaceholder) {
                  setState(() => _priceIsPlaceholder = false);
                }
              },
              decoration: InputDecoration(
                labelText: '售价（元）*',
                hintText: '请填写售价',
                border: const OutlineInputBorder(),
                suffixIcon: _clearIcon(_priceCtrl, _priceFocus),
              ),
            ),
            const SizedBox(height: 8),

            // 懒人芯片
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.history, size: 18),
                  label: const Text('上次价'),
                  onPressed: _fillLastPrice,
                ),
                _chip('抹零', () {
                  final v = double.tryParse(_priceCtrl.text);
                  if (v == null) return;
                  _priceCtrl.text = v.ceilToDouble().toStringAsFixed(2);
                  setState(() => _priceIsPlaceholder = false);
                }),
                _chip('+0.5', () {
                  final v = double.tryParse(_priceCtrl.text) ?? 0;
                  _priceCtrl.text = (v + 0.5).toStringAsFixed(2);
                  setState(() => _priceIsPlaceholder = false);
                }),
                _chip('-0.5', () {
                  final v = double.tryParse(_priceCtrl.text) ?? 0;
                  if (v >= 0.5) {
                    _priceCtrl.text = (v - 0.5).toStringAsFixed(2);
                    setState(() => _priceIsPlaceholder = false);
                  }
                }),
              ],
            ),
            const SizedBox(height: 24),

            // 保存按钮组
            if (_isEditing)
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('保存修改', style: TextStyle(fontSize: 16)),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: _saving ? null : _save,
                        child: const Text(
                          '保存并返回',
                          style: TextStyle(fontSize: 15),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _saveAndContinue,
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                '保存并继续',
                                style: TextStyle(fontSize: 15),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, VoidCallback onTap) {
    return ActionChip(label: Text(label), onPressed: onTap);
  }
}
