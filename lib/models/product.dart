// lib/models/product.dart
class Product {
  int? id;
  String barcode;
  String name;
  String? brand;
  String? spec;
  String category; // ← 新增，默认 ''
  double sellingPrice;
  String? localImagePath;
  String imageSource;
  int updateTime;

  Product({
    this.id,
    required this.barcode,
    required this.name,
    this.brand,
    this.spec,
    this.category = '',
    required this.sellingPrice,
    this.localImagePath,
    this.imageSource = 'none',
    required this.updateTime,
  });

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'],
      barcode: map['barcode'],
      name: map['name'],
      brand: map['brand'],
      spec: map['spec'],
      category: map['category'] ?? '',
      sellingPrice: (map['selling_price'] as num).toDouble(),
      localImagePath: map['local_image_path'],
      imageSource: map['image_source'] ?? 'none',
      updateTime: map['update_time'],
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
      'update_time': updateTime,
    };
  }

  Product copyWith({
    int? id,
    String? barcode,
    String? name,
    String? brand,
    String? spec,
    String? category,
    double? sellingPrice,
    String? localImagePath,
    String? imageSource,
    int? updateTime,
  }) {
    return Product(
      id: id ?? this.id,
      barcode: barcode ?? this.barcode,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      spec: spec ?? this.spec,
      category: category ?? this.category,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      localImagePath: localImagePath ?? this.localImagePath,
      imageSource: imageSource ?? this.imageSource,
      updateTime: updateTime ?? this.updateTime,
    );
  }
}
