// lib/utils/app_toast.dart
import 'dart:async';

import 'package:flutter/material.dart';

/// 全局 Navigator Key。
///
/// AppToast 通过它拿到 [Overlay]，因此调用处无需再传 `context`。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// 顶部轻提示（AppBar 下方浮层，从上方滑入滑出）。
///
/// 反馈位置分级规则的落地实现：临时/重要提示走顶部，不遮挡底部操作按钮。
/// - [info]：纯提示，1.5 秒
/// - [action]：带动作按钮，2 秒
///
/// 连续调用时只保留最新一条。
class AppToast {
  AppToast._();

  static OverlayEntry? _entry;

  /// 纯提示，1.5 秒。
  static void info(String message) {
    _show(message: message, duration: const Duration(milliseconds: 1500));
  }

  /// 带动作的提示，2 秒。
  static void action(
    String message, {
    String actionLabel = '查看',
    VoidCallback? onAction,
  }) {
    _show(
      message: message,
      duration: const Duration(milliseconds: 2000),
      actionLabel: onAction == null ? null : actionLabel,
      onAction: onAction,
    );
  }

  /// 立即移除当前提示。
  static void dismiss() {
    final entry = _entry;
    _entry = null;
    if (entry != null && entry.mounted) entry.remove();
  }

  static void _show({
    required String message,
    required Duration duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final overlay = appNavigatorKey.currentState?.overlay;
    if (overlay == null) return;

    dismiss();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _AppToastWidget(
        message: message,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
        onFinished: () {
          if (identical(_entry, entry)) _entry = null;
          if (entry.mounted) entry.remove();
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }
}

class _AppToastWidget extends StatefulWidget {
  const _AppToastWidget({
    required this.message,
    required this.duration,
    required this.onFinished,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onFinished;

  @override
  State<_AppToastWidget> createState() => _AppToastWidgetState();
}

class _AppToastWidgetState extends State<_AppToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 180),
  );

  late final Animation<Offset> _offset =
      Tween<Offset>(begin: const Offset(0, -1.4), end: Offset.zero).animate(
        CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic),
      );

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _anim.forward();
    _timer = Timer(widget.duration, _hide);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  Future<void> _hide() async {
    _timer?.cancel();
    _timer = null;
    if (!mounted) return;
    await _anim.reverse();
    if (mounted) widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + kToolbarHeight + 8;

    Widget card = Material(
      color: Colors.black.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(10),
      elevation: 6,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          14,
          10,
          widget.actionLabel == null ? 14 : 6,
          10,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                widget.message,
                style: const TextStyle(color: Colors.white, fontSize: 13.5),
              ),
            ),
            if (widget.actionLabel != null) ...[
              const SizedBox(width: 4),
              TextButton(
                onPressed: () {
                  widget.onAction?.call();
                  _hide();
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.lightBlueAccent,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(widget.actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );

    // 纯提示不拦截点击，避免挡住 AppBar 交互
    if (widget.actionLabel == null) {
      card = IgnorePointer(child: card);
    }

    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _offset,
        child: FadeTransition(
          opacity: _anim,
          child: Align(alignment: Alignment.topCenter, child: card),
        ),
      ),
    );
  }
}
