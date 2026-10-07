// lib/database/product_dao.dart
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';
import '../models/product.dart';

class ProductDao {
  final DatabaseHelper _helper = DatabaseHelper();

  // 插入新商品，返回插入行的 id
  Future<int> insertProduct(Product product) async {
    final db = await _helper.database;
    final map = product.toMap();
    // 注意：id 由数据库自动生成，我们不传入
    return await db.insert('products', map);
  }

  // 更新商品（根据 id）
  Future<int> updateProduct(Product product) async {
    final db = await _helper.database;
    if (product.id == null) {
      throw Exception('Cannot update product without id');
    }
    return await db.update(
      'products',
      product.toMap(),
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  // 根据条码查询商品（精确匹配）
  Future<Product?> getProductByBarcode(String barcode) async {
    final db = await _helper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'products',
      where: 'barcode = ?',
      whereArgs: [barcode],
    );
    if (maps.isNotEmpty) {
      return Product.fromMap(maps.first);
    }
    return null;
  }

  // 根据 id 查询
  Future<Product?> getProductById(int id) async {
    final db = await _helper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Product.fromMap(maps.first);
    }
    return null;
  }

  // 查询所有商品（按更新时间倒序）
  Future<List<Product>> getAllProducts() async {
    final db = await _helper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'products',
      orderBy: 'update_time DESC',
    );
    return maps.map((map) => Product.fromMap(map)).toList();
  }

  // 删除商品（物理删除，但本系统建议先移入回收站，这里保留仅用于特殊情况）
  Future<int> deleteProductById(int id) async {
    final db = await _helper.database;
    return await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  // 检查主表中条码是否存在（供回收站恢复时使用》
  Future<bool> existsBarcode(String barcode) async {
    final db = await _helper.database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM products WHERE barcode = ?', [
        barcode,
      ]),
    );
    return count != null && count > 0;
  }

  // 批量插入（用于测试或导入）
  Future<void> insertProducts(List<Product> products) async {
    final db = await _helper.database;
    final batch = db.batch();
    for (var p in products) {
      batch.insert('products', p.toMap());
    }
    await batch.commit(noResult: true);
  }
}
