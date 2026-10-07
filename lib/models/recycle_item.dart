// lib/models/recycle_item.dart
import 'product.dart';

class RecycleItem {
  int? id;
  String barcode;
  String name;
  String? brand;
  String? spec;
  String category;
  double sellingPrice;
  String? localImagePath;
  String imageSource;
  int imageSize;
  int deletedAt;

  RecycleItem({
    this.id,
    required this.barcode,
    required this.name,
    this.brand,
    this.spec,
    this.category = '',
    required this.sellingPrice,
    this.localImagePath,
    this.imageSource = 'none',
    this.imageSize = 0,
    required this.deletedAt,
  });

  // 从 Product 创建 RecycleItem
  factory RecycleItem.fromProduct(Product p) {
    return RecycleItem(
      barcode: p.barcode,
      name: p.name,
      brand: p.brand,
      spec: p.spec,
      category: p.category,
      sellingPrice: p.sellingPrice,
      localImagePath: p.localImagePath,
      imageSource: p.imageSource,
      deletedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory RecycleItem.fromMap(Map<String, dynamic> map) {
    return RecycleItem(
      id: map['id'],
      barcode: map['barcode'] ?? '',
      name: map['name'],
      brand: map['brand'],
      spec: map['spec'],
      category: map['category'] ?? '',
      sellingPrice: (map['selling_price'] as num?)?.toDouble() ?? 0,
      localImagePath: map['local_image_path'],
      imageSource: map['image_source'] ?? 'none',
      imageSize: map['image_size'] ?? 0,
      deletedAt: map['deleted_at'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'barcode': barcode,
      'name': name,
      'brand': brand,
      'spec': spec,
      'category': category,
      'selling_price': sellingPrice,
      'local_image_path': localImagePath,
      'image_source': imageSource,
      'image_size': imageSize,
      'deleted_at': deletedAt,
    };
  }

  // 转回 Product（用于恢复）
  Product toProduct() {
    return Product(
      barcode: barcode,
      name: name,
      brand: brand,
      spec: spec,
      category: category,
      sellingPrice: sellingPrice,
      localImagePath: localImagePath,
      imageSource: imageSource,
      updateTime: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
