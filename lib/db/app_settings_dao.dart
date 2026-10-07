// lib/db/app_settings_dao.dart
import 'database_helper.dart';

import 'package:sqflite/sqflite.dart';

class AppSettingsDao {
  final DatabaseHelper _helper = DatabaseHelper();

  /// 读取一个键
  Future<String?> get(String key) async {
    final db = await _helper.database;
    final maps = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return maps.first['value'] as String?;
  }

  /// 写入一个键（覆盖）
  Future<void> set(String key, String value) async {
    final db = await _helper.database;
    await db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
