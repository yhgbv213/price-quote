// test/widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:price_query_app/utils/app_toast.dart';
import 'package:price_query_app/widgets/app_bar_icon_button.dart';

void main() {
  testWidgets('AppToast.info 在顶部浮层显示，并在 1.5 秒后自动消失', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );

    AppToast.info('已自动分配序号 AUTO_5');
    await tester.pump(); // 插入 Overlay
    await tester.pump(const Duration(milliseconds: 300)); // 滑入完成

    expect(find.text('已自动分配序号 AUTO_5'), findsOneWidget);

    // 1.5 秒后自动消失（含滑出动画）
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('已自动分配序号 AUTO_5'), findsNothing);
  });

  group('AppBarIconButton（复现项目主题：useMaterial3 = false）', () {
    /// [useComponent] = false 时故意用老写法（Stack 直接塞进 actions），
    /// 用来记录 AppBar 在 M2 下 stretch 造成的偏移。
    Widget buildAppBar({required bool useComponent}) {
      return MaterialApp(
        theme: ThemeData(useMaterial3: false, primarySwatch: Colors.blue),
        home: Scaffold(
          appBar: AppBar(
            actions: [
              if (useComponent)
                AppBarIconButton(
                  icon: Icons.delete_outline,
                  tooltip: '回收站',
                  badgeCount: 3,
                  onPressed: () {},
                )
              else
                Stack(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {},
                    ),
                    const Positioned(right: 0, top: 0, child: Text('3')),
                  ],
                ),
              IconButton(icon: const Icon(Icons.settings), onPressed: () {}),
            ],
          ),
        ),
      );
    }

    testWidgets('带角标的图标应与普通图标垂直居中', (tester) async {
      await tester.pumpWidget(buildAppBar(useComponent: true));

      final badgeIcon = tester.getCenter(find.byIcon(Icons.delete_outline));
      final plainIcon = tester.getCenter(find.byIcon(Icons.settings));

      expect(
        badgeIcon.dy,
        closeTo(plainIcon.dy, 0.5),
        reason: '带角标的图标必须与旁边图标基线齐平',
      );
    });

    testWidgets('记录框架行为：老写法（Stack 直接进 actions）确实偏上', (tester) async {
      await tester.pumpWidget(buildAppBar(useComponent: false));

      final stacked = tester.getCenter(find.byIcon(Icons.delete_outline));
      final plain = tester.getCenter(find.byIcon(Icons.settings));
      final offset = plain.dy - stacked.dy;

      debugPrint('[验证] 老写法垂直偏移 = $offset dp（正数 = 偏上）');
      expect(
        offset,
        greaterThan(0),
        reason: 'AppBar 在 useMaterial3=false 时用 stretch，Stack 内容贴顶',
      );
    });
  });
}
