// lib/models/quote.dart
class Quote {
  int? id;
  String? name; // 保存时生成"报价单 YYYYMMDD HH:mm"，可改
  String? customer; // 客户名（可空）
  String? note; // 备注（可空）
  double totalPrice; // 总价快照
  int itemCount; // 总件数（SUM(quantity)）
  String status; // 'draft' | 'saved'
  int createdAt;
  int updatedAt;

  Quote({
    this.id,
    this.name,
    this.customer,
    this.note,
    this.totalPrice = 0,
    this.itemCount = 0,
    this.status = 'draft',
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isDraft => status == 'draft';
  bool get isSaved => status == 'saved';

  factory Quote.fromMap(Map<String, dynamic> m) {
    return Quote(
      id: m['id'],
      name: m['name'],
      customer: m['customer'],
      note: m['note'],
      totalPrice: (m['total_price'] as num?)?.toDouble() ?? 0,
      itemCount: m['item_count'] ?? 0,
      status: m['status'] ?? 'draft',
      createdAt: m['created_at'],
      updatedAt: m['updated_at'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'customer': customer,
      'note': note,
      'total_price': totalPrice,
      'item_count': itemCount,
      'status': status,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  Quote copyWith({
    int? id,
    String? name,
    String? customer,
    String? note,
    double? totalPrice,
    int? itemCount,
    String? status,
    int? createdAt,
    int? updatedAt,
  }) {
    return Quote(
      id: id ?? this.id,
      name: name ?? this.name,
      customer: customer ?? this.customer,
      note: note ?? this.note,
      totalPrice: totalPrice ?? this.totalPrice,
      itemCount: itemCount ?? this.itemCount,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
