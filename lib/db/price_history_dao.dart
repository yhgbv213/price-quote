// lib/db/price_history_dao.dart
// import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';
import '../utils/constants.dart';

class PriceHistoryDao {
  final DatabaseHelper _helper = DatabaseHelper();

  // 插入一条价格历史（并保持每商品最多 AppConstants.priceHistoryMaxPerProduct 条）
  Future<void> insert({required String barcode, required double price}) async {
    final db = await _helper.database;

    // 1. 插入新记录
    await db.insert('price_history', {
      'barcode': barcode,
      'price': price,
      'record_time': DateTime.now().millisecondsSinceEpoch,
    });

    // 2. 查询该条码的所有历史，按时间倒序
    final list = await db.query(
      'price_history',
      where: 'barcode = ?',
      whereArgs: [barcode],
      orderBy: 'record_time DESC',
    );

    // 3. 超过上限，删掉最旧的
    if (list.length > AppConstants.priceHistoryMaxPerProduct) {
      for (
        int i = AppConstants.priceHistoryMaxPerProduct;
        i < list.length;
        i++
      ) {
        await db.delete(
          'price_history',
          where: 'id = ?',
          whereArgs: [list[i]['id']],
        );
      }
    }
  }

  // 读取某条码的最新一次价格
  Future<double?> getLatestPrice(String barcode) async {
    final db = await _helper.database;
    final maps = await db.query(
      'price_history',
      where: 'barcode = ?',
      whereArgs: [barcode],
      orderBy: 'record_time DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return (maps.first['price'] as num).toDouble();
  }
}
