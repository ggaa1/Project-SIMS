class OcrDraftItem {
  String name;
  String category;
  String quantity;
  DateTime expireDate;

  /// 유통기한 계수 (OCR 산출, 기본 1.0). 카테고리 표준 보관일수에 곱해
  /// 만료일을 산정할 때 사용. expiry-spec-v1.md §4.1
  double coefficient;

  OcrDraftItem({
    required this.name,
    required this.category,
    required this.quantity,
    DateTime? expireDate,
    this.coefficient = 1.0,
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
    final rawCoef = json['coefficient'];

    DateTime? parsedExpire;
    if (rawExpire is String && rawExpire.isNotEmpty) {
      // 서버는 UTC instant(KST 자정 환산)로 보냄 → 로컬(KST)로 변환해야
      // 날짜 컴포넌트가 하루 어긋나지 않는다.
      parsedExpire = DateTime.tryParse(rawExpire)?.toLocal();
    }

    double parsedCoef = 1.0;
    if (rawCoef is num) {
      parsedCoef = rawCoef.toDouble();
    } else if (rawCoef is String) {
      parsedCoef = double.tryParse(rawCoef) ?? 1.0;
    }

    return OcrDraftItem(
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '기타',
      quantity: rawQuantity == null ? '1' : rawQuantity.toString(),
      expireDate: parsedExpire,
      coefficient: parsedCoef,
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
