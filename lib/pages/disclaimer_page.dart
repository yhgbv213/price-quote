// lib/pages/disclaimer_page.dart
import 'package:flutter/material.dart';

/// 免责声明标题
const String kDisclaimerTitle = '数据来源与免责声明';

/// 重要提示（加粗显著显示）
const String kDisclaimerImportantNotice = '重要提示：本声明中关于免除或限制责任的内容，请您仔细阅读。';

/// 免责声明正文
const String kDisclaimerBody = '''
1. 本应用为中立的技术工具，所有商品信息均来自用户自行配置的第三方API服务。本应用不生成、不编辑、不推荐任何商品数据。

2. 本应用不对任何第三方数据的准确性、完整性、及时性或合法性作出保证。商品信息仅供参考，请以商品实物为准。

3. 用户在使用第三方API服务时，应遵守该服务提供者的服务条款。因用户违反第三方服务条款而产生的任何责任，由用户自行承担。

4. 本应用提供的缓存功能，仅用于提升用户查询效率。用户通过本应用分享的任何数据，其行为及后果由用户自行负责。

5. 本应用不面向不满十四周岁的未成年人。如您是未成年人，请在监护人指导下使用本应用。

6. 如权利人认为通过本应用获取的数据侵犯其合法权益，可通过关于页联系方式通知我们，我们将依法及时处理。

7. 撤回同意：您可随时通过「设置 → 清空所有数据」撤回本同意，并删除所有本地数据。撤回后，本应用将无法继续为您提供服务，您需要重新打开并同意本声明才能再次使用。
''';

/// 免责声明内容组件（可嵌入弹窗或独立页面）
class DisclaimerContent extends StatelessWidget {
  const DisclaimerContent({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          const Text(
            kDisclaimerTitle,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // 重要提示（橙色警告框 + 加粗）
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.orange.shade900.withValues(alpha: 0.3)
                  : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? Colors.orange.shade800 : Colors.orange.shade200,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: isDark
                      ? Colors.orange.shade300
                      : Colors.orange.shade800,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    kDisclaimerImportantNotice,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? Colors.orange.shade200
                          : const Color(0xFFE65100),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 正文
          const Text(
            kDisclaimerBody,
            style: TextStyle(fontSize: 14, height: 1.8),
          ),
        ],
      ),
    );
  }
}

/// 完整免责声明页面（从关于页进入）
class DisclaimerFullPage extends StatelessWidget {
  const DisclaimerFullPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('用户协议与免责声明')),
      body: const DisclaimerContent(),
    );
  }
}
