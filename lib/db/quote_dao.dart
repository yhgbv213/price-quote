// lib/db/quote_dao.dart
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';
import '../models/quote.dart';
import '../models/quote_item.dart';

class QuoteDao {
  final DatabaseHelper _helper = DatabaseHelper();

  // ============ 草稿相关 ============

  /// 加载当前草稿（status='draft'，取最新一条）
  Future<Quote?> getDraft() async {
    final db = await _helper.database;
    final maps = await db.query(
      'quotes',
      where: 'status = ?',
      whereArgs: ['draft'],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Quote.fromMap(maps.first);
  }

  /// 创建草稿，返回新 id
  Future<int> createDraft() async {
    final db = await _helper.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return await db.insert('quotes', {
      'name': null,
      'customer': null,
      'note': null,
      'total_price': 0.0,
      'item_count': 0,
      'status': 'draft',
      'created_at': now,
      'updated_at': now,
    });
  }

  /// 更新草稿的汇总字段
  Future<void> updateDraftTotals({
    required int quoteId,
    required double totalPrice,
    required int itemCount,
    String? name,
    String? customer,
    String? note,
  }) async {
    final db = await _helper.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'quotes',
      {
        'total_price': totalPrice,
        'item_count': itemCount,
        'name': name,
        'customer': customer,
        'note': note,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [quoteId],
    );
  }

  /// 草稿转正（方案 A：原地改 status）
  Future<void> markAsSaved(int quoteId, {String? name}) async {
    final db = await _helper.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'quotes',
      {'status': 'saved', 'name': name, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [quoteId],
    );
  }

  /// 物理删除（含明细，靠外键级联）
  Future<void> deleteQuote(int quoteId) async {
    final db = await _helper.database;
    await db.delete('quotes', where: 'id = ?', whereArgs: [quoteId]);
  }

  // ============ 历史列表 ============

  /// 已保存列表
  Future<List<Quote>> getSavedList({
    String orderBy = 'updated_at DESC',
    String? keyword,
  }) async {
    final db = await _helper.database;
    String where = "status = 'saved'";
    List<dynamic> args = [];
    if (keyword != null && keyword.trim().isNotEmpty) {
      where += " AND (name LIKE ? OR customer LIKE ?)";
      final kw = '%${keyword.trim()}%';
      args = [kw, kw];
    }
    final maps = await db.query(
      'quotes',
      where: where,
      whereArgs: args,
      orderBy: orderBy,
    );
    return maps.map((m) => Quote.fromMap(m)).toList();
  }

  /// 已保存数量
  Future<int> countSaved() async {
    final db = await _helper.database;
    final r = await db.rawQuery(
      "SELECT COUNT(*) FROM quotes WHERE status = 'saved'",
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  /// 取最旧的 N 条已保存记录（LRU 淘汰用）
  Future<List<Quote>> getOldestSaved(int limit) async {
    final db = await _helper.database;
    final maps = await db.query(
      'quotes',
      where: "status = 'saved'",
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return maps.map((m) => Quote.fromMap(m)).toList();
  }

  /// 按 id 查详情
  Future<Quote?> getById(int id) async {
    final db = await _helper.database;
    final maps = await db.query(
      'quotes',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Quote.fromMap(maps.first);
  }

  // ============ 全量替换明细 + 汇总（单事务）============

  /// 用途：debounce 后一次性落库；300ms 内的多次改动合并为一次写入
  Future<void> replaceDraftWithItems({
    required Quote quote,
    required List<QuoteItem> items,
  }) async {
    final db = await _helper.database;
    await db.transaction((txn) async {
      // 1. 删除旧明细
      await txn.delete(
        'quote_items',
        where: 'quote_id = ?',
        whereArgs: [quote.id],
      );
      // 2. 插入当前内存中的所有明细
      for (final item in items) {
        await txn.insert(
          'quote_items',
          item.copyWith(quoteId: quote.id).toMap(),
        );
      }
      // 3. 更新主表汇总
      await txn.update(
        'quotes',
        {
          'name': quote.name,
          'customer': quote.customer,
          'note': quote.note,
          'total_price': quote.totalPrice,
          'item_count': quote.itemCount,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [quote.id],
      );
    });
  }
}
