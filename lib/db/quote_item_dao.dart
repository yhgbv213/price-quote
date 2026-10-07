// lib/db/quote_item_dao.dart
import 'database_helper.dart';
import '../models/quote_item.dart';

class QuoteItemDao {
  final DatabaseHelper _helper = DatabaseHelper();

  /// 查询某报价单的所有明细（按加入时间升序）
  Future<List<QuoteItem>> getByQuoteId(int quoteId) async {
    final db = await _helper.database;
    final maps = await db.query(
      'quote_items',
      where: 'quote_id = ?',
      whereArgs: [quoteId],
      orderBy: 'created_at ASC',
    );
    return maps.map((m) => QuoteItem.fromMap(m)).toList();
  }

  /// 插入一行，返回新 id
  Future<int> insert(QuoteItem item) async {
    final db = await _helper.database;
    return await db.insert('quote_items', item.toMap());
  }

  /// 更新一行（数量、小计）
  Future<void> update(QuoteItem item) async {
    final db = await _helper.database;
    await db.update(
      'quote_items',
      {'quantity': item.quantity, 'subtotal': item.subtotal},
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  /// 删除一行
  Future<void> deleteById(int id) async {
    final db = await _helper.database;
    await db.delete('quote_items', where: 'id = ?', whereArgs: [id]);
  }

  /// 清空某报价单的所有明细
  Future<void> deleteByQuoteId(int quoteId) async {
    final db = await _helper.database;
    await db.delete('quote_items', where: 'quote_id = ?', whereArgs: [quoteId]);
  }

  /// 统计某报价单的行数（不同商品种数）
  Future<int> countByQuoteId(int quoteId) async {
    final db = await _helper.database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) FROM quote_items WHERE quote_id = ?',
      [quoteId],
    );
    return (r.first.values.first as int?) ?? 0;
  }
}
