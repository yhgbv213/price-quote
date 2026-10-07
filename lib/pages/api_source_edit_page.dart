// lib/pages/api_source_edit_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/api_source.dart';
import '../providers/api_source_provider.dart';
import '../utils/mask_util.dart';

class ApiSourceEditPage extends StatefulWidget {
  /// 传 null = 新增；非 null = 编辑
  final ApiSource? source;

  const ApiSourceEditPage({super.key, this.source});

  @override
  State<ApiSourceEditPage> createState() => _ApiSourceEditPageState();
}

class _ApiSourceEditPageState extends State<ApiSourceEditPage> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _headersCtrl;
  late final TextEditingController _paramsCtrl;
  late final TextEditingController _bodyCtrl;
  late final TextEditingController _responsePathCtrl;
  late final TextEditingController _timeoutCtrl;

  late String _method;

  // 页面级"显示敏感信息"开关
  bool _showSensitive = false;
  // 字段级临时显示（字段名 → 是否临时显示）
  final Map<String, bool> _fieldRevealed = {};

  bool get _isEditing => widget.source != null;

  @override
  void initState() {
    super.initState();
    final s = widget.source;
    _nameCtrl = TextEditingController(text: s?.name ?? '');
    _urlCtrl = TextEditingController(text: s?.baseUrl ?? '');
    _headersCtrl = TextEditingController(text: s?.headers ?? '');
    _paramsCtrl = TextEditingController(text: s?.paramsTemplate ?? '');
    _bodyCtrl = TextEditingController(text: s?.bodyTemplate ?? '');
    _responsePathCtrl = TextEditingController(text: s?.responsePath ?? '');
    _timeoutCtrl = TextEditingController(
      text: (s?.timeoutSeconds ?? 3).toString(),
    );
    _method = s?.method ?? 'GET';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _headersCtrl.dispose();
    _paramsCtrl.dispose();
    _bodyCtrl.dispose();
    _responsePathCtrl.dispose();
    _timeoutCtrl.dispose();
    super.dispose();
  }

  // ============ 保存 ============
  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final url = _urlCtrl.text.trim();
    if (name.isEmpty) {
      _snack('请填写名称');
      return;
    }
    if (url.isEmpty) {
      _snack('请填写 URL 模板');
      return;
    }
    if (!url.contains('{barcode}')) {
      _snack('URL 必须包含 {barcode} 占位符');
      return;
    }
    final timeout = int.tryParse(_timeoutCtrl.text.trim()) ?? 3;

    final provider = context.read<ApiSourceProvider>();

    if (_isEditing) {
      final updated = widget.source!.copyWith(
        name: name,
        baseUrl: url,
        method: _method,
        headers: _emptyToNull(_headersCtrl.text),
        paramsTemplate: _emptyToNull(_paramsCtrl.text),
        bodyTemplate: _emptyToNull(_bodyCtrl.text),
        responsePath: _emptyToNull(_responsePathCtrl.text),
        timeoutSeconds: timeout,
      );
      await provider.updateSource(updated);
      if (!mounted) return;
      _snack('已保存');
    } else {
      await provider.addSource(
        name: name,
        baseUrl: url,
        method: _method,
        headers: _emptyToNull(_headersCtrl.text),
        paramsTemplate: _emptyToNull(_paramsCtrl.text),
        bodyTemplate: _emptyToNull(_bodyCtrl.text),
        responsePath: _emptyToNull(_responsePathCtrl.text),
        timeoutSeconds: timeout,
      );
      if (!mounted) return;
      _snack('已添加，默认禁用，需手动启用');
    }
    Navigator.pop(context);
  }

  String? _emptyToNull(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ============ 切换敏感显示（页面级） ============
  void _toggleGlobalSensitive() {
    setState(() {
      _showSensitive = !_showSensitive;
      _fieldRevealed.clear();
    });
    if (_showSensitive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('敏感信息已显示，请注意周围环境'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ============ 渲染敏感字段输入框 ============
  Widget _buildSensitiveField({
    required String label,
    required String fieldKey,
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
  }) {
    final revealed = _showSensitive || (_fieldRevealed[fieldKey] ?? false);
    final hasContent = controller.text.isNotEmpty;

    // 决定显示文本：显示时用原文，隐藏时用掩码
    // 为了让用户能编辑，我们让 TextField 始终绑定 controller，
    // 但显示时如果未 reveal，用 obscureText 效果不太对（掩码是定长）
    // 折中：用 obscureText = !revealed（星号代替）
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: revealed ? maxLines : 1,
        obscureText: !revealed && hasContent,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: Icon(revealed ? Icons.visibility_off : Icons.visibility),
            tooltip: revealed ? '隐藏' : '临时显示',
            onPressed: () {
              setState(() {
                _fieldRevealed[fieldKey] = !revealed;
              });
            },
          ),
        ),
      ),
    );
  }

  // ============ 普通字段（URL 特殊处理） ============
  Widget _buildUrlField() {
    final revealed = _showSensitive;
    // final hasContent = _urlCtrl.text.isNotEmpty;
    final hasKey = MaskUtil.urlHasKey(_urlCtrl.text);
    // final needMask = hasContent && hasKey && !revealed;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _urlCtrl,
        decoration: InputDecoration(
          labelText: 'URL 模板',
          hintText: 'https://api.example.com/?barcode={barcode}',
          helperText: '必须包含 {barcode} 占位符',
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
          suffixIcon: hasKey
              ? IconButton(
                  icon: Icon(
                    revealed ? Icons.visibility_off : Icons.visibility,
                  ),
                  tooltip: revealed ? '隐藏' : '临时显示',
                  onPressed: () {
                    setState(() => _showSensitive = !revealed);
                  },
                )
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑数据源' : '新增数据源'),
        actions: [
          // 页面级显示敏感开关
          IconButton(
            icon: Icon(
              _showSensitive ? Icons.visibility_off : Icons.visibility,
            ),
            tooltip: _showSensitive ? '隐藏敏感信息' : '显示敏感信息',
            onPressed: _toggleGlobalSensitive,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: '名称 *',
              hintText: '例如：我的私有 API',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          _buildUrlField(),

          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _method,
              decoration: const InputDecoration(
                labelText: '请求方式',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'GET', child: Text('GET')),
                DropdownMenuItem(value: 'POST', child: Text('POST')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _method = v);
              },
            ),
          ),

          _buildSensitiveField(
            label: '请求头（可选）',
            fieldKey: 'headers',
            controller: _headersCtrl,
            hint: 'JSON 格式，例如 {"Authorization":"Bearer xxx"}',
            maxLines: 3,
          ),

          _buildSensitiveField(
            label: '参数模板（可选）',
            fieldKey: 'params',
            controller: _paramsCtrl,
            hint: '例如 key=xxx&code={barcode}',
          ),

          _buildSensitiveField(
            label: '请求体模板（可选，POST）',
            fieldKey: 'body',
            controller: _bodyCtrl,
            hint: '支持 {barcode} 占位符',
            maxLines: 3,
          ),

          TextField(
            controller: _responsePathCtrl,
            decoration: const InputDecoration(
              labelText: '响应解析路径（可选）',
              hintText: '例如 data.name 或 data.name_zh|data.name',
              helperText: '支持 | 分隔多路径，取第一个非空',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _timeoutCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '超时时间（秒）',
              hintText: '默认 3',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),

          // 测试按钮（暂只提示）
          OutlinedButton.icon(
            icon: const Icon(Icons.network_check),
            label: const Text('测试请求'),
            onPressed: () {
              _snack('测试功能开发中...');
            },
          ),
          const SizedBox(height: 8),

          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _save,
              child: Text(_isEditing ? '保存' : '添加'),
            ),
          ),
        ],
      ),
    );
  }
}
