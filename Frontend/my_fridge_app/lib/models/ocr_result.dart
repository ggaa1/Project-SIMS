class OcrDraftItem {
  String name;
  String category;
  String quantity;
  DateTime expireDate;

  OcrDraftItem({
    required this.name,
    required this.category,
    required this.quantity,
    DateTime? expireDate,
  }) : expireDate = expireDate ??
            DateTime.now().add(const Duration(days: 7));

  int get count {
    return int.tryParse(quantity.trim()) ?? 1;
  }

  String get expireDateString {
    return '${expireDate.year.toString().padLeft(4, '0')}-'
        '${expireDate.month.toString().padLeft(2, '0')}-'
        '${expireDate.day.toString().padLeft(2, '0')}';
  }

  factory OcrDraftItem.fromJson(Map<String, dynamic> json) {
    final rawQuantity = json['quantity'];
    final rawExpire = json['expireDate'] ?? json['expire_date'];

    DateTime? parsedExpire;
    if (rawExpire is String && rawExpire.isNotEmpty) {
      parsedExpire = DateTime.tryParse(rawExpire);
    }

    return OcrDraftItem(
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '기타',
      quantity: rawQuantity == null ? '1' : rawQuantity.toString(),
      expireDate: parsedExpire,
    );
  }
}

class OcrResult {
  final String sourceKind;
  final List<OcrDraftItem> items;
  final String model;

  const OcrResult({
    required this.sourceKind,
    required this.items,
    required this.model,
  });

  factory OcrResult.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];

    return OcrResult(
      sourceKind: json['source_kind'] as String? ?? '',
      items: rawItems
          .map((item) => OcrDraftItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      model: json['model'] as String? ?? '',
    );
  }
}
