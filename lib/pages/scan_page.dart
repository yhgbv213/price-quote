// lib/pages/scan_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// 扫码页工作模式
enum ScanMode {
  /// 单次扫码：扫到即返回并关闭（编辑页用）
  single,

  /// 连续扫码：扫到不关闭，可连续累积（报价单页用）
  continuous,
}

/// 连续扫码每次扫到的反馈，由调用方返回，用于顶部芯片提示
class ScanFeedback {
  /// 顶部中间短暂提示（2 秒），如"已添加：可乐" / "未找到：xxx"
  final String message;

  /// 顶部左侧常驻计数（报价单共 M 件）
  final int totalCount;

  /// 该条码在本地商品库中不存在（退出扫码后提示补录）
  final bool notFound;

  const ScanFeedback({
    required this.message,
    required this.totalCount,
    this.notFound = false,
  });
}

/// 连续扫码处理器：返回给扫码页用来显示提示
typedef ScanHandler = Future<ScanFeedback> Function(String barcode);

class ScanPage extends StatefulWidget {
  /// 扫码模式：single（默认，扫到即返回）/ continuous（连续累积）
  final ScanMode mode;

  /// 连续模式下的扫到回调（连续模式必传）
  final ScanHandler? onScanned;

  /// 连续模式下顶部常驻计数的初始值
  final int initialCount;

  const ScanPage({
    super.key,
    this.mode = ScanMode.single,
    this.onScanned,
    this.initialCount = 0,
  });

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  /// 同一条码的重复触发冷却时间。
  /// 连续模式下摄像头对准同一件商品会持续上报，冷却避免"一次对准"被重复计数。
  static const int _repeatCooldownMs = 1800;

  late final MobileScannerController _controller = MobileScannerController(
    // 单次模式去重；连续模式需允许同一条码重复扫（数量 +1）
    detectionSpeed: widget.mode == ScanMode.single
        ? DetectionSpeed.noDuplicates
        : DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _hasScanned = false;

  // ===== 连续模式状态 =====
  bool _busy = false;
  String? _lastCode;
  int _lastAcceptAt = 0;
  int _totalCount = 0;
  String? _recentMessage;
  Timer? _recentTimer;

  /// 本次连续扫码中扫到、但本地库没有的条码（退出时带回上一页）
  final Set<String> _notFoundCodes = {};

  @override
  void initState() {
    super.initState();
    _totalCount = widget.initialCount;
  }

  @override
  void dispose() {
    _recentTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty) return;

    if (widget.mode == ScanMode.single) {
      if (_hasScanned) return;
      _hasScanned = true;
      Navigator.pop(context, code); // 把扫到的条码返回给上一页
      return;
    }

    _handleContinuous(code);
  }

  Future<void> _handleContinuous(String code) async {
    final handler = widget.onScanned;
    if (handler == null || _busy) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (code == _lastCode && now - _lastAcceptAt < _repeatCooldownMs) return;

    _busy = true;
    _lastCode = code;
    try {
      final feedback = await handler(code);
      if (!mounted) return;
      if (feedback.notFound) _notFoundCodes.add(code);
      setState(() {
        _totalCount = feedback.totalCount;
        _recentMessage = feedback.message;
      });
      _recentTimer?.cancel();
      _recentTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _recentMessage = null);
      });
    } finally {
      _busy = false;
      _lastAcceptAt = DateTime.now().millisecondsSinceEpoch;
    }
  }

  /// 退出连续扫码：把"未建档"条码带回报价单页
  void _finishContinuous() {
    Navigator.pop(context, _notFoundCodes.toList());
  }

  @override
  Widget build(BuildContext context) {
    final isContinuous = widget.mode == ScanMode.continuous;

    final page = Scaffold(
      appBar: AppBar(
        title: Text(isContinuous ? '连续扫码' : '扫码'),
        actions: [
          // 手电筒开关
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          // 前后摄像头切换
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          ),
          if (isContinuous)
            TextButton(
              onPressed: _finishContinuous,
              child: const Text('完成', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // 中间一个扫描框
          Center(
            child: Container(
              width: 260,
              height: 180,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.greenAccent, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          // 连续模式：顶部芯片（左侧常驻计数 + 中间临时提示）
          if (isContinuous)
            Positioned(top: 12, left: 12, right: 12, child: _buildTopChips())
          else
            const Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Text(
                '将摄像头对准商品条码',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
        ],
      ),
    );

    if (!isContinuous) return page;

    // 连续模式：系统返回键也要带上"未建档"列表
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _finishContinuous();
      },
      child: page,
    );
  }

  /// 顶部芯片：左侧"报价单共 M 件"常驻，中间临时提示 2 秒消失。
  /// 不用全屏 Toast，避免盖住扫描框。
  Widget _buildTopChips() {
    return Row(
      children: [
        _chip('报价单共 $_totalCount 件', opaque: true),
        const SizedBox(width: 8),
        if (_recentMessage != null)
          Flexible(child: _chip(_recentMessage!, opaque: false)),
      ],
    );
  }

  Widget _chip(String text, {required bool opaque}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: opaque ? Colors.black87 : Colors.black54,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }
}
