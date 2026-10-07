// lib/services/image_service.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../utils/constants.dart';

class ImageService {
  final ImagePicker _picker = ImagePicker();

  /// 从相册选图，返回临时文件（null = 用户取消）
  Future<File?> pickFromGallery() async {
    final xfile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100, // 原始质量，压缩交给我们的 compute
    );
    if (xfile == null) return null;
    return File(xfile.path);
  }

  /// 拍照，返回临时文件（null = 用户取消）
  Future<File?> pickFromCamera() async {
    final xfile = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 100,
    );
    if (xfile == null) return null;
    return File(xfile.path);
  }

  /// 保存商品图片：压缩 → 存到私有目录/images/{barcode}.jpg
  /// 返回相对路径（如 images/6901234567890.jpg）
  Future<String?> saveProductImage({
    required String barcode,
    required File source,
    bool isLowEndDevice = false,
  }) async {
    try {
      // 1. 读取原图字节
      final bytes = await source.readAsBytes();

      // 2. 用 compute 在后台 Isolate 里压缩
      final compressed = await compute(
        _compressImage,
        _CompressArgs(
          bytes: bytes,
          maxLongSide: isLowEndDevice
              ? AppConstants.imageMaxLongSideLowEnd
              : AppConstants.imageMaxLongSide,
          quality: isLowEndDevice
              ? AppConstants.imageQualityLowEnd
              : AppConstants.imageQuality,
        ),
      );
      if (compressed == null) return null;

      // 3. 确保目录存在
      final docDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(path.join(docDir.path, 'images'));
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }

      // 4. 写入目标文件（覆盖旧图）
      final fileName = '$barcode.jpg';
      final target = File(path.join(imagesDir.path, fileName));
      await target.writeAsBytes(compressed);

      // 5. 返回相对路径
      return 'images/$fileName';
    } catch (e) {
      if (AppConstants.kApiDebug) {
        debugPrint('[ImageService] 保存图片失败: $e');
      }
      return null;
    }
  }

  /// 根据相对路径得到 File（用于 Image.file）
  Future<File?> resolveFile(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) return null;
    final docDir = await getApplicationDocumentsDirectory();
    final file = File(path.join(docDir.path, relativePath));
    if (await file.exists()) return file;
    return null;
  }

  /// 同步版本：直接拼接路径（用于 FutureBuilder 内部）
  Future<File> resolveFileOrPlaceholder(String relativePath) async {
    final docDir = await getApplicationDocumentsDirectory();
    return File(path.join(docDir.path, relativePath));
  }

  /// 删除商品图片
  Future<void> deleteProductImage(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) return;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final file = File(path.join(docDir.path, relativePath));
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

// ============ Isolate 参数 ============
class _CompressArgs {
  final Uint8List bytes;
  final int maxLongSide;
  final int quality;
  _CompressArgs({
    required this.bytes,
    required this.maxLongSide,
    required this.quality,
  });
}

// ============ 压缩函数（运行在 Isolate） ============
Uint8List? _compressImage(_CompressArgs args) {
  try {
    final decoded = img.decodeImage(args.bytes);
    if (decoded == null) return null;

    // 计算压缩后的尺寸（长边不超过 maxLongSide）
    int w = decoded.width;
    int h = decoded.height;
    final longSide = w > h ? w : h;
    if (longSide > args.maxLongSide) {
      final ratio = args.maxLongSide / longSide;
      w = (w * ratio).round();
      h = (h * ratio).round();
    }

    final resized = img.copyResize(decoded, width: w, height: h);
    final jpg = img.encodeJpg(resized, quality: args.quality);
    return Uint8List.fromList(jpg);
  } catch (_) {
    return null;
  }
}
