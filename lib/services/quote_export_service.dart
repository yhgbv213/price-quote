// lib/services/quote_export_service.dart
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/quote.dart';
import '../models/quote_item.dart';

class QuoteExportService {
  /// 导出报价单为 Excel 并调起分享
  Future<void> exportAndShare(Quote quote, List<QuoteItem> items) async {
    if (items.isEmpty) {
      throw Exception('报价单为空，无内容可导出');
    }

    final bytes = _buildExcel(quote, items);
    final dir = await getTemporaryDirectory();

    // 文件名：报价单名去非法字符
    final rawName = quote.name ?? '报价单';
    final safeName = rawName.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    final fileName = '$safeName.xlsx';
    final file = File(path.join(dir.path, fileName));
    await file.writeAsBytes(bytes);

    try {
      await Share.shareXFiles([
        XFile(
          file.path,
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ], subject: fileName);
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  List<int> _buildExcel(Quote quote, List<QuoteItem> items) {
    final excel = Excel.createExcel();
    final sheet = excel['报价单'];
    excel.delete('Sheet1');

    int row = 0;

    // ============ 头部：标题 ============
    final titleCell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
    );
    titleCell.value = TextCellValue(quote.name ?? '报价单');
    titleCell.cellStyle = CellStyle(bold: true, fontSize: 16);
    row++;

    // ============ 客户 / 时间 ============
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue(
      '客户：${quote.customer?.isNotEmpty == true ? quote.customer : "-"}',
    );
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
        .value = TextCellValue(
      '日期：${_formatTime(quote.createdAt)}',
    );
    row++;

    // ============ 备注（如果有）============
    if (quote.note != null && quote.note!.isNotEmpty) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = TextCellValue(
        '备注：${quote.note}',
      );
      row++;
    }

    row++; // 空一行

    // ============ 表头 ============
    final headers = ['序号', '名称', '规格', '单价', '数量', '小计'];
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row),
      );
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#DDEBF7'),
      );
    }
    row++;

    // ============ 明细 ============
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = IntCellValue(
        i + 1,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          .value = TextCellValue(
        it.name,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
          .value = TextCellValue(
        it.spec ?? '',
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
          .value = DoubleCellValue(
        double.parse(it.unitPrice.toStringAsFixed(2)),
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
          .value = IntCellValue(
        it.quantity,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row))
          .value = DoubleCellValue(
        double.parse(it.subtotal.toStringAsFixed(2)),
      );
      row++;
    }

    // ============ 合计 ============
    final sumLabelCell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
    );
    sumLabelCell.value = TextCellValue('合计');
    sumLabelCell.cellStyle = CellStyle(bold: true);

    final sumQtyCell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row),
    );
    sumQtyCell.value = IntCellValue(quote.itemCount);
    sumQtyCell.cellStyle = CellStyle(bold: true);

    final sumPriceCell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row),
    );
    sumPriceCell.value = DoubleCellValue(
      double.parse(quote.totalPrice.toStringAsFixed(2)),
    );
    sumPriceCell.cellStyle = CellStyle(bold: true);

    // ============ 列宽 ============
    sheet.setColumnWidth(0, 6); // 序号
    sheet.setColumnWidth(1, 30); // 名称
    sheet.setColumnWidth(2, 14); // 规格
    sheet.setColumnWidth(3, 10); // 单价
    sheet.setColumnWidth(4, 8); // 数量
    sheet.setColumnWidth(5, 12); // 小计

    return excel.encode() ?? [];
  }

  String _formatTime(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    return DateFormat('yyyy-MM-dd HH:mm').format(dt);
  }
}
