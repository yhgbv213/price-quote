// lib/models/quote_item.dart
class QuoteItem {
  int? id;
  int quoteId;
  String barcode;
  String name;
  String? spec;
  double unitPrice; // 单价快照
  int quantity;
  double subtotal; // 小计快照 = unitPrice × quantity
  int createdAt; // 该行加入报价单的时间（审计用）

  QuoteItem({
    this.id,
    required this.quoteId,
    required this.barcode,
    required this.name,
    this.spec,
    required this.unitPrice,
    this.quantity = 1,
    required this.subtotal,
    required this.createdAt,
  });

  factory QuoteItem.fromMap(Map<String, dynamic> m) {
    return QuoteItem(
      id: m['id'],
      quoteId: m['quote_id'],
      barcode: m['barcode'],
      name: m['name'],
      spec: m['spec'],
      unitPrice: (m['unit_price'] as num).toDouble(),
      quantity: m['quantity'] ?? 1,
      subtotal: (m['subtotal'] as num).toDouble(),
      createdAt: m['created_at'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'quote_id': quoteId,
      'barcode': barcode,
      'name': name,
      'spec': spec,
      'unit_price': unitPrice,
      'quantity': quantity,
      'subtotal': subtotal,
      'created_at': createdAt,
    };
  }

  QuoteItem copyWith({
    int? id,
    int? quoteId,
    String? barcode,
    String? name,
    String? spec,
    double? unitPrice,
    int? quantity,
    double? subtotal,
    int? createdAt,
  }) {
    return QuoteItem(
      id: id ?? this.id,
      quoteId: quoteId ?? this.quoteId,
      barcode: barcode ?? this.barcode,
      name: name ?? this.name,
      spec: spec ?? this.spec,
      unitPrice: unitPrice ?? this.unitPrice,
      quantity: quantity ?? this.quantity,
      subtotal: subtotal ?? this.subtotal,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
