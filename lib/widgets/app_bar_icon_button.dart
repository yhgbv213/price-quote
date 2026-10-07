// lib/widgets/app_bar_icon_button.dart
import 'package:flutter/material.dart';

/// AppBar 右侧图标按钮（可选数量角标）。
///
/// **为什么需要它**
///
/// AppBar 在 `useMaterial3 = false` 时，actions 用的 Row 是
/// `CrossAxisAlignment.stretch` —— 会把每个**直接子项**拉伸到 toolbar 全高
/// （kToolbarHeight = 56dp）。由此产生两种结果：
///
/// - 裸 [IconButton]：内部会把图标垂直居中 → 看不出问题
/// - 带角标的图标：必须用 Stack / Badge 包裹，而它们默认把内容对齐到**顶部**
///   → 48dp 的按钮贴在 56dp 的顶部 → 比旁边图标高出 4dp，角标也跟着"飘"
///
/// 这里用 [Center] 包住「按钮 + 角标」，让整体保持自身高度并垂直居中，
/// 从根上消除这类错位。
///
/// 用法：
/// ```dart
/// AppBarIconButton(
///   icon: Icons.delete_outline,
///   tooltip: '回收站',
///   badgeCount: provider.recycleCount,
///   onPressed: _goRecycle,
/// )
/// ```
class AppBarIconButton extends StatelessWidget {
  const AppBarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// 角标数字；<= 0 时不显示角标
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: onPressed,
    );

    // 无角标：裸 IconButton 本身就会被 AppBar 正确居中，不必多包一层
    if (badgeCount <= 0) return button;

    // 有角标：Stack / Badge 默认顶对齐，必须用 Center 抵消 AppBar 的 stretch
    return Center(
      child: Badge.count(
        count: badgeCount,
        maxCount: 99,
        backgroundColor: Colors.red,
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
        child: button,
      ),
    );
  }
}
