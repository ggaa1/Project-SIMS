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

    final parsed = rawItems
        .map((item) => OcrDraftItem.fromJson(item as Map<String, dynamic>))
        .toList();

    return OcrResult(
      sourceKind: json['source_kind'] as String? ?? '',
      items: _dedupeItems(parsed),
      model: json['model'] as String? ?? '',
    );
  }

  /// 같은 (이름, 카테고리)는 한 항목으로 합치고 수량을 더한다.
  /// Gemini 환각으로 같은 객체가 여러 번 추출되는 케이스 대응.
  /// 이름 비교는 공백·대소문자 무시.
  static List<OcrDraftItem> _dedupeItems(List<OcrDraftItem> items) {
    final result = <OcrDraftItem>[];
    final indexByKey = <String, int>{};
    for (final item in items) {
      final normalized = item.name.trim().toLowerCase();
      if (normalized.isEmpty) {
        result.add(item);
        continue;
      }
      final key = '$normalized|${item.category}';
      final existingIdx = indexByKey[key];
      if (existingIdx == null) {
        indexByKey[key] = result.length;
        result.add(item);
      } else {
        // 기존 항목과 합치기: 수량 합산, 유통기한은 더 가까운 쪽
        final existing = result[existingIdx];
        final mergedCount = existing.count + item.count;
        existing.quantity = mergedCount.toString();
        if (item.expireDate.isBefore(existing.expireDate)) {
          existing.expireDate = item.expireDate;
        }
      }
    }
    return result;
  }
}
