// lib/db/recycle_dao.dart
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';
import '../models/recycle_item.dart';

class RecycleDao {
  final DatabaseHelper _helper = DatabaseHelper();

  // 插入回收站记录
  Future<int> insert(RecycleItem item) async {
    final db = await _helper.database;
    return await db.insert('recycle_bin', item.toMap());
  }

  // 查询全部回收站记录（按删除时间倒序）
  Future<List<RecycleItem>> getAll() async {
    final db = await _helper.database;
    final maps = await db.query('recycle_bin', orderBy: 'deleted_at DESC');
    return maps.map((m) => RecycleItem.fromMap(m)).toList();
  }

  // 统计数量（用于角标）
  Future<int> count() async {
    final db = await _helper.database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM recycle_bin');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // 按 id 删除一条
  Future<int> deleteById(int id) async {
    final db = await _helper.database;
    return await db.delete('recycle_bin', where: 'id = ?', whereArgs: [id]);
  }

  // 清空回收站
  Future<int> clearAll() async {
    final db = await _helper.database;
    return await db.delete('recycle_bin');
  }
}
