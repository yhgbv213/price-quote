// lib/services/export_service.dart
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

import '../models/product.dart';

class ExportService {
  /// 导出商品列表为 Excel，返回分享结果
  /// 失败时抛异常，调用方捕获并 Toast
  Future<void> exportProducts(List<Product> products) async {
    if (products.isEmpty) {
      throw Exception('暂无数据，请先添加商品');
    }

    // 1. 生成 Excel 字节流
    final bytes = _buildExcel(products);

    // 2. 写入临时文件
    final dir = await getTemporaryDirectory();
    final today = DateFormat('yyyyMMdd').format(DateTime.now());
    final fileName = '商品报价_$today.xlsx';
    final file = File(path.join(dir.path, fileName));
    await file.writeAsBytes(bytes);

    // 3. 调起系统分享
    try {
      await Share.shareXFiles([
        XFile(
          file.path,
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ], subject: fileName);
    } finally {
      // 4. 分享面板关闭后，立即删除临时文件
      //（不管用户是否真的发送，只要面板关闭就删）
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // 删除失败不影响主流程
      }
    }
  }

  /// 构建 Excel 字节流
  List<int> _buildExcel(List<Product> products) {
    final excel = Excel.createExcel();
    // 默认有个 Sheet1，重命名为"商品报价"
    final sheet = excel['商品报价'];
    excel.delete('Sheet1');

    // 表头
    final headers = ['条码', '名称', '品牌', '规格', '分类', '售价', '图片文件名', '更新时间'];
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#DDEBF7'),
      );
    }

    // 数据行
    for (var r = 0; r < products.length; r++) {
      final p = products[r];
      final rowIndex = r + 1;

      // 条码
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex))
          .value = TextCellValue(
        p.barcode,
      );
      // 名称
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex))
          .value = TextCellValue(
        p.name,
      );
      // 品牌
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex))
          .value = TextCellValue(
        p.brand ?? '',
      );
      // 规格
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex))
          .value = TextCellValue(
        p.spec ?? '',
      );
      // 分类
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex))
          .value = TextCellValue(
        p.category.isEmpty ? '未分类' : p.category,
      );
      // 售价（保留 2 位小数）
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex))
          .value = DoubleCellValue(
        double.parse(p.sellingPrice.toStringAsFixed(2)),
      );
      // 图片文件名
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIndex))
          .value = TextCellValue(
        p.localImagePath == null ? '' : path.basename(p.localImagePath!),
      );
      // 更新时间（yyyy-MM-dd HH:mm）
      final dt = DateTime.fromMillisecondsSinceEpoch(p.updateTime);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIndex))
          .value = TextCellValue(
        DateFormat('yyyy-MM-dd HH:mm').format(dt),
      );
    }

    // 列宽（字符宽度）
    sheet.setColumnWidth(0, 18);
    sheet.setColumnWidth(1, 28);
    sheet.setColumnWidth(2, 16);
    sheet.setColumnWidth(3, 12);
    sheet.setColumnWidth(4, 10);
    sheet.setColumnWidth(5, 10);
    sheet.setColumnWidth(6, 18);
    sheet.setColumnWidth(7, 18);

    return excel.encode() ?? [];
  }
}
