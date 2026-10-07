// lib/db/database_helper.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

import '../utils/constants.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = path.join(dir.path, 'price_query.db');
    return await openDatabase(
      dbPath,
      version: AppConstants.dbVersion, // V6.0.1：升到 10（自动扫码开关）
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  // ==================== 首次创建 ====================
  Future<void> _onCreate(Database db, int version) async {
    await db.transaction((txn) async {
      // 1. 商品主表
      await txn.execute('''
        CREATE TABLE products (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          barcode TEXT NOT NULL UNIQUE,
          name TEXT NOT NULL,
          brand TEXT,
          spec TEXT,
          category TEXT DEFAULT '',
          selling_price REAL NOT NULL DEFAULT 0,
          local_image_path TEXT,
          image_source TEXT DEFAULT 'none',
          update_time INTEGER NOT NULL
        )
      ''');
      await txn.execute(
        'CREATE INDEX idx_search_cover ON products(name, barcode, brand, spec)',
      );
      await txn.execute('CREATE INDEX idx_barcode ON products(barcode)');
      await txn.execute(
        'CREATE INDEX idx_update_time ON products(update_time DESC)',
      );
      await txn.execute('CREATE INDEX idx_category ON products(category)');

      // 2. 回收站
      await txn.execute('''
        CREATE TABLE recycle_bin (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          barcode TEXT,
          name TEXT NOT NULL,
          brand TEXT,
          spec TEXT,
          category TEXT,
          selling_price REAL,
          local_image_path TEXT,
          image_source TEXT,
          image_size INTEGER DEFAULT 0,
          deleted_at INTEGER NOT NULL
        )
      ''');
      await txn.execute(
        'CREATE INDEX idx_recycle_deleted ON recycle_bin(deleted_at)',
      );
      await txn.execute(
        'CREATE INDEX idx_recycle_barcode ON recycle_bin(barcode)',
      );

      // 3. 缓存
      await txn.execute('''
        CREATE TABLE barcode_cache (
          barcode TEXT PRIMARY KEY,
          api_response TEXT NOT NULL,
          cached_at INTEGER NOT NULL,
          source_name TEXT
        )
      ''');
      await txn.execute(
        'CREATE INDEX idx_cache_cached_at ON barcode_cache(cached_at)',
      );

      // 4. 价格历史
      await txn.execute('''
        CREATE TABLE price_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          barcode TEXT NOT NULL,
          price REAL NOT NULL,
          record_time INTEGER NOT NULL
        )
      ''');
      await txn.execute(
        'CREATE INDEX idx_history_barcode ON price_history(barcode)',
      );

      // 5. API 源
      await txn.execute('''
        CREATE TABLE api_sources (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          base_url TEXT NOT NULL,
          method TEXT DEFAULT 'GET',
          headers TEXT,
          params_template TEXT,
          body_template TEXT,
          response_path TEXT,
          is_builtin INTEGER DEFAULT 0,
          is_protected INTEGER DEFAULT 0,
          enabled INTEGER DEFAULT 0,
          priority INTEGER DEFAULT 100,
          timeout_seconds INTEGER DEFAULT 3,
          created_at INTEGER NOT NULL
        )
      ''');

      // 6. 应用设置
      await txn.execute('''
        CREATE TABLE app_settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');

      // 7. 报价单主表
      await txn.execute('''
        CREATE TABLE quotes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT,
          customer TEXT,
          note TEXT,
          total_price REAL NOT NULL,
          item_count INTEGER NOT NULL,
          status TEXT DEFAULT 'draft',
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await txn.execute(
        'CREATE INDEX idx_quotes_created ON quotes(created_at DESC)',
      );
      await txn.execute('CREATE INDEX idx_quotes_customer ON quotes(customer)');
      await txn.execute('CREATE INDEX idx_quotes_name ON quotes(name)');
      await txn.execute('CREATE INDEX idx_quotes_status ON quotes(status)');

      // 8. 报价单明细
      await txn.execute('''
        CREATE TABLE quote_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          quote_id INTEGER NOT NULL,
          barcode TEXT NOT NULL,
          name TEXT NOT NULL,
          spec TEXT,
          unit_price REAL NOT NULL,
          quantity INTEGER NOT NULL DEFAULT 1,
          subtotal REAL NOT NULL,
          created_at INTEGER NOT NULL,
          FOREIGN KEY (quote_id) REFERENCES quotes(id) ON DELETE CASCADE
        )
      ''');
      await txn.execute(
        'CREATE INDEX idx_quote_items_quote ON quote_items(quote_id)',
      );

      // ---------- 初始数据 ----------
      final now = DateTime.now().millisecondsSinceEpoch;

      final defaultSettings = {
        'free_mode_tip_shown': 'false',
        'image_reuse_choice': '',
        'ignored_orphan_ids': '[]',
        'custom_categories': '[]',
        'sort_mode': AppConstants.defaultSortMode,
        'cache_max_count': AppConstants.cacheMaxCount.toString(),
        'cache_expire_days': AppConstants.cacheExpireDays.toString(),
        'cache_enabled': 'true', // V5.1 新增
        'theme_mode': AppConstants.defaultThemeMode,
        'show_dashboard': 'true',
        'disclaimer_agreed_at': '',
        'disclaimer_version': '',
        'auto_scan_after_save_continue': 'false', // V6.0.1 新增
        'db_version': AppConstants.dbVersion.toString(),
      };
      for (final entry in defaultSettings.entries) {
        await txn.insert('app_settings', {
          'key': entry.key,
          'value': entry.value,
        });
      }

      // ============ 内置数据源 ============
      // 1. 极数本源（默认禁用，用户自主启用）
      await txn.insert('api_sources', {
        'name': '极数本源',
        'base_url':
            'https://v1.apizero.cn/api/barcode-lookup?barcode={barcode}',
        'method': 'GET',
        'headers': null,
        'params_template': null,
        'body_template': null,
        'response_path': 'name:data.name|brand:data.brand|spec:data.spec|image_url:data.image',
        'is_builtin': 1,
        'is_protected': 0,
        'enabled': 0, // ← 默认禁用
        'priority': 1,
        'timeout_seconds': 5,
        'created_at': now,
      });

      // 2. Open Food Facts
      await txn.insert('api_sources', {
        'name': 'Open Food Facts',
        'base_url':
            'https://world.openfoodfacts.org/api/v2/product/{barcode}.json',
        'method': 'GET',
        'headers': null,
        'params_template': null,
        'body_template': null,
        'response_path': 'name:product.product_name_zh|product.product_name|brand:product.brands|spec:product.quantity|image_url:product.image_url',
        'is_builtin': 1,
        'is_protected': 1,
        'enabled': 1,
        'priority': 2,
        'timeout_seconds': 3,
        'created_at': now,
      });

      // 3. 阿里云
      await txn.insert('api_sources', {
        'name': '阿里云条形码API',
        'base_url':
            'https://barcode14.market.alicloudapi.com/barcode?code={barcode}',
        'method': 'GET',
        'headers': '{"Authorization":"APPCODE 你的AppCode"}',
        'params_template': null,
        'body_template': null,
        'response_path': 'name:showapi_res_body.goodsName|brand:showapi_res_body.manuName|spec:showapi_res_body.spec|image_url:showapi_res_body.img',
        'is_builtin': 1,
        'is_protected': 0,
        'enabled': 0,
        'priority': 3,
        'timeout_seconds': 3,
        'created_at': now,
      });
    });
  }

  // ==================== 升级 ====================
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 测试版本
    if (AppConstants.kApiDebug) {
      debugPrint('[DB] 迁移: $oldVersion → $newVersion');
    }

    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE products ADD COLUMN category TEXT DEFAULT ''",
      );
      await db.execute('ALTER TABLE recycle_bin ADD COLUMN category TEXT');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_category ON products(category)',
      );
      await db.insert('app_settings', {
        'key': 'custom_categories',
        'value': '[]',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    if (oldVersion < 3) {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_cache_cached_at ON barcode_cache(cached_at)',
      );
      final newKeys = {
        'cache_max_count': AppConstants.cacheMaxCount.toString(),
        'cache_expire_days': AppConstants.cacheExpireDays.toString(),
        'theme_mode': AppConstants.defaultThemeMode,
        'show_dashboard': 'true',
        'sort_mode': AppConstants.defaultSortMode,
      };
      for (final entry in newKeys.entries) {
        await db.insert('app_settings', {
          'key': entry.key,
          'value': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }

    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS quotes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT,
          customer TEXT,
          note TEXT,
          total_price REAL NOT NULL,
          item_count INTEGER NOT NULL,
          status TEXT DEFAULT 'draft',
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS quote_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          quote_id INTEGER NOT NULL,
          barcode TEXT NOT NULL,
          name TEXT NOT NULL,
          spec TEXT,
          unit_price REAL NOT NULL,
          quantity INTEGER NOT NULL DEFAULT 1,
          subtotal REAL NOT NULL,
          created_at INTEGER NOT NULL,
          FOREIGN KEY (quote_id) REFERENCES quotes(id) ON DELETE CASCADE
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_created ON quotes(created_at DESC)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_customer ON quotes(customer)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_name ON quotes(name)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_status ON quotes(status)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_quote_items_quote ON quote_items(quote_id)',
      );
    }

    if (oldVersion < 5) {
      await db.update(
        'api_sources',
        {
          'response_path': 'name:product.product_name_zh|product.product_name|brand:product.brands|spec:product.quantity|image_url:product.image_url',
        },
        where: 'name = ?',
        whereArgs: ['Open Food Facts'],
      );
      await db.update(
        'api_sources',
        {
          'base_url':
              'https://barcode14.market.alicloudapi.com/barcode?code={barcode}',
          'headers': '{"Authorization":"APPCODE 你的AppCode"}',
          'response_path': 'name:showapi_res_body.goodsName|brand:showapi_res_body.manuName|spec:showapi_res_body.spec|image_url:showapi_res_body.img',
        },
        where: 'name = ?',
        whereArgs: ['阿里云条形码API'],
      );
    }

    if (oldVersion < 6) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final existing = await db.query(
        'api_sources',
        where: 'name = ?',
        whereArgs: ['极数本源'],
        limit: 1,
      );
      if (existing.isEmpty) {
        await db.insert('api_sources', {
          'name': '极数本源',
          'base_url':
              'https://v1.apizero.cn/api/barcode-lookup?barcode={barcode}',
          'method': 'GET',
          'headers': null,
          'params_template': null,
          'body_template': null,
          'response_path': 'name:data.name|brand:data.brand|spec:data.spec|image_url:data.image',
          'is_builtin': 1,
          'is_protected': 0,
          'enabled': 1,
          'priority': 1,
          'timeout_seconds': 5,
          'created_at': now,
        });
      }
      await db.update(
        'api_sources',
        {'priority': 2},
        where: 'name = ?',
        whereArgs: ['Open Food Facts'],
      );
      await db.update(
        'api_sources',
        {'priority': 3},
        where: 'name = ?',
        whereArgs: ['阿里云条形码API'],
      );
    }

    // V5.1：缓存总开关
    if (oldVersion < 7) {
      await db.insert('app_settings', {
        'key': 'cache_enabled',
        'value': 'true',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // V5.2：缓存加源名字段
    if (oldVersion < 8) {
      await db.execute('ALTER TABLE barcode_cache ADD COLUMN source_name TEXT');
    }

    // V5.3：免责声明同意记录
    if (oldVersion < 9) {
      await db.insert('app_settings', {
        'key': 'disclaimer_agreed_at',
        'value': '',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await db.insert('app_settings', {
        'key': 'disclaimer_version',
        'value': '',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // V6.0.1（DB v10）：保存并继续后自动扫码开关
    if (oldVersion < 10) {
      await db.insert('app_settings', {
        'key': 'auto_scan_after_save_continue',
        'value': 'false',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    await db.insert('app_settings', {
      'key': 'db_version',
      'value': newVersion.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ============ 清空所有数据 ============
  Future<void> clearAllData() async {
    final db = _database;
    if (db == null) return;

    await db.transaction((txn) async {
      await txn.delete('products');
      await txn.delete('recycle_bin');
      await txn.delete('barcode_cache');
      await txn.delete('price_history');
      await txn.delete('quote_items');
      await txn.delete('quotes');
      await txn.delete('api_sources');
      await txn.delete('app_settings');

      final defaults = {
        'free_mode_tip_shown': 'false',
        'image_reuse_choice': '',
        'ignored_orphan_ids': '[]',
        'custom_categories': '[]',
        'sort_mode': AppConstants.defaultSortMode,
        'cache_max_count': AppConstants.cacheMaxCount.toString(),
        'cache_expire_days': AppConstants.cacheExpireDays.toString(),
        'cache_enabled': 'true',
        'theme_mode': AppConstants.defaultThemeMode,
        'show_dashboard': 'true',
        'disclaimer_agreed_at': '',
        'disclaimer_version': '',
        'auto_scan_after_save_continue': 'false', // V6.0.1 新增
        'db_version': AppConstants.dbVersion.toString(),
      };
      for (final e in defaults.entries) {
        await txn.insert('app_settings', {'key': e.key, 'value': e.value});
      }

      final now = DateTime.now().millisecondsSinceEpoch;

      // 极数本源
      await txn.insert('api_sources', {
        'name': '极数本源',
        'base_url':
            'https://v1.apizero.cn/api/barcode-lookup?barcode={barcode}',
        'method': 'GET',
        'headers': null,
        'params_template': null,
        'body_template': null,
        'response_path': 'name:data.name|brand:data.brand|spec:data.spec|image_url:data.image',
        'is_builtin': 1,
        'is_protected': 0,
        'enabled': 0,
        'priority': 1,
        'timeout_seconds': 5,
        'created_at': now,
      });

      // Open Food Facts
      await txn.insert('api_sources', {
        'name': 'Open Food Facts',
        'base_url':
            'https://world.openfoodfacts.org/api/v2/product/{barcode}.json',
        'method': 'GET',
        'headers': null,
        'params_template': null,
        'body_template': null,
        'response_path': 'name:product.product_name_zh|product.product_name|brand:product.brands|spec:product.quantity|image_url:product.image_url',
        'is_builtin': 1,
        'is_protected': 1,
        'enabled': 1,
        'priority': 2,
        'timeout_seconds': 3,
        'created_at': now,
      });

      // 阿里云
      await txn.insert('api_sources', {
        'name': '阿里云条形码API',
        'base_url':
            'https://barcode14.market.alicloudapi.com/barcode?code={barcode}',
        'method': 'GET',
        'headers': '{"Authorization":"APPCODE 你的AppCode"}',
        'params_template': null,
        'body_template': null,
        'response_path': 'name:showapi_res_body.goodsName|brand:showapi_res_body.manuName|spec:showapi_res_body.spec|image_url:showapi_res_body.img',
        'is_builtin': 1,
        'is_protected': 0,
        'enabled': 0,
        'priority': 3,
        'timeout_seconds': 3,
        'created_at': now,
      });
    });
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
