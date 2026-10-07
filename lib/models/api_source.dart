// lib/models/api_source.dart
class ApiSource {
  final int? id;
  final String name;
  final String baseUrl;
  final String method; // GET / POST
  final String? headers;
  final String? paramsTemplate;
  final String? bodyTemplate;
  final String? responsePath; // 支持 | 分隔多路径
  final bool isBuiltin;
  final bool isProtected;
  final bool enabled;
  final int priority;
  final int timeoutSeconds;

  ApiSource({
    this.id,
    required this.name,
    required this.baseUrl,
    this.method = 'GET',
    this.headers,
    this.paramsTemplate,
    this.bodyTemplate,
    this.responsePath,
    this.isBuiltin = false,
    this.isProtected = false,
    this.enabled = false,
    this.priority = 100,
    this.timeoutSeconds = 3,
  });

  factory ApiSource.fromMap(Map<String, dynamic> m) {
    return ApiSource(
      id: m['id'],
      name: m['name'],
      baseUrl: m['base_url'],
      method: m['method'] ?? 'GET',
      headers: m['headers'],
      paramsTemplate: m['params_template'],
      bodyTemplate: m['body_template'],
      responsePath: m['response_path'],
      isBuiltin: (m['is_builtin'] ?? 0) == 1,
      isProtected: (m['is_protected'] ?? 0) == 1,
      enabled: (m['enabled'] ?? 0) == 1,
      priority: m['priority'] ?? 100,
      timeoutSeconds: m['timeout_seconds'] ?? 3,
    );
  }

  ApiSource copyWith({
    int? id,
    String? name,
    String? baseUrl,
    String? method,
    String? headers,
    String? paramsTemplate,
    String? bodyTemplate,
    String? responsePath,
    bool? isBuiltin,
    bool? isProtected,
    bool? enabled,
    int? priority,
    int? timeoutSeconds,
  }) {
    return ApiSource(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      method: method ?? this.method,
      headers: headers ?? this.headers,
      paramsTemplate: paramsTemplate ?? this.paramsTemplate,
      bodyTemplate: bodyTemplate ?? this.bodyTemplate,
      responsePath: responsePath ?? this.responsePath,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      isProtected: isProtected ?? this.isProtected,
      enabled: enabled ?? this.enabled,
      priority: priority ?? this.priority,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    );
  }
}
