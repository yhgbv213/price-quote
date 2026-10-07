// lib/db/api_source_dao.dart
import 'database_helper.dart';
import '../models/api_source.dart';

class ApiSourceDao {
  final DatabaseHelper _helper = DatabaseHelper();

  /// 读取所有启用的源（按 priority 升序）
  Future<List<ApiSource>> getEnabledSources() async {
    final db = await _helper.database;
    final maps = await db.query(
      'api_sources',
      where: 'enabled = 1',
      orderBy: 'priority ASC',
    );
    return maps.map((m) => ApiSource.fromMap(m)).toList();
  }

  /// 读取所有源（含禁用，按 priority 升序）
  Future<List<ApiSource>> getAllSources() async {
    final db = await _helper.database;
    final maps = await db.query('api_sources', orderBy: 'priority ASC');
    return maps.map((m) => ApiSource.fromMap(m)).toList();
  }

  /// 按 id 查询
  Future<ApiSource?> getById(int id) async {
    final db = await _helper.database;
    final maps = await db.query(
      'api_sources',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return ApiSource.fromMap(maps.first);
  }

  /// 插入
  Future<int> insert(ApiSource source) async {
    final db = await _helper.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return await db.insert('api_sources', {
      'name': source.name,
      'base_url': source.baseUrl,
      'method': source.method,
      'headers': source.headers,
      'params_template': source.paramsTemplate,
      'body_template': source.bodyTemplate,
      'response_path': source.responsePath,
      'is_builtin': source.isBuiltin ? 1 : 0,
      'is_protected': source.isProtected ? 1 : 0,
      'enabled': source.enabled ? 1 : 0,
      'priority': source.priority,
      'timeout_seconds': source.timeoutSeconds,
      'created_at': now,
    });
  }

  /// 更新
  Future<void> update(ApiSource source) async {
    final db = await _helper.database;
    await db.update(
      'api_sources',
      {
        'name': source.name,
        'base_url': source.baseUrl,
        'method': source.method,
        'headers': source.headers,
        'params_template': source.paramsTemplate,
        'body_template': source.bodyTemplate,
        'response_path': source.responsePath,
        'enabled': source.enabled ? 1 : 0,
        'priority': source.priority,
        'timeout_seconds': source.timeoutSeconds,
      },
      where: 'id = ?',
      whereArgs: [source.id],
    );
  }

  /// 启用/禁用
  Future<void> setEnabled(int id, bool enabled) async {
    final db = await _helper.database;
    await db.update(
      'api_sources',
      {'enabled': enabled ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 删除
  Future<void> delete(int id) async {
    final db = await _helper.database;
    await db.delete('api_sources', where: 'id = ?', whereArgs: [id]);
  }

  /// 取最大 priority（用于新增时排到最后）
  Future<int> getMaxPriority() async {
    final db = await _helper.database;
    final r = await db.rawQuery(
      'SELECT MAX(priority) as max_p FROM api_sources',
    );
    final v = r.first['max_p'];
    return (v as int?) ?? 0;
  }

  /// 判断是否可以删除（返回错误信息，null 表示可删）
  Future<String?> canDelete(ApiSource source) async {
    if (source.isProtected) {
      return '免费兜底源不可删除，防止无源可用';
    }
    if (source.enabled) {
      return '请先禁用该数据源，再执行删除';
    }
    return null;
  }
}
