// lib/pages/disclaimer_gate.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import 'disclaimer_page.dart';

import 'package:flutter/services.dart';

/// 启动门：未同意免责声明时，显示同意弹窗；同意后放行 child
class DisclaimerGate extends StatelessWidget {
  final Widget child;
  const DisclaimerGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    // SettingsProvider 还没加载完 → 显示空白（避免闪烁）
    if (!settings.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 需要同意 → 显示同意页
    if (settings.needsDisclaimerAgreement) {
      return const _DisclaimerAgreeScreen();
    }

    // 已同意 → 放行
    return child;
  }
}

class _DisclaimerAgreeScreen extends StatelessWidget {
  const _DisclaimerAgreeScreen();

  Future<void> _onDisagree(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认退出'),
        content: const Text('不同意用户协议与免责声明将无法使用本应用。\n\n确认退出？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    // 退出到桌面
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 禁止返回键退出页面（必须点同意或退出 App）
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('用户协议与免责声明'),
          automaticallyImplyLeading: false, // 无返回按钮
        ),
        body: const DisclaimerContent(),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _onDisagree(context),
                    child: const Text('不同意'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () async {
                      await context.read<SettingsProvider>().agreeDisclaimer();
                    },
                    child: const Text('我已阅读并同意'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
