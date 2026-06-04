import 'dart:convert';

import 'api_client.dart';

/// 카테고리별 표준 보관일수 1건 (전역+냉장고 override 머지 결과).
class CategoryShelfLife {
  final String category;
  final int days;
  final bool isCustom; // 이 냉장고가 override 한 값이면 true

  const CategoryShelfLife({
    required this.category,
    required this.days,
    required this.isCustom,
  });

  factory CategoryShelfLife.fromJson(Map<String, dynamic> json) {
    return CategoryShelfLife(
      category: json['category'] as String? ?? '',
      days: (json['days'] as num?)?.toInt() ?? 7,
      isCustom: json['isCustom'] as bool? ?? false,
    );
  }
}

/// `/fridges/{id}/category-shelf-life` 연동.
/// 유통기한 자동 산정 기본값(전역) + 냉장고 override 를 조회/수정한다.
/// (expiry-spec-v1.md §5)
class CategoryShelfLifeService {
  CategoryShelfLifeService._();

  static String _path(String fridgeId) =>
      '/fridges/$fridgeId/category-shelf-life';

  /// 12종 머지 결과 조회.
  static Future<List<CategoryShelfLife>> getList(String fridgeId) async {
    final body = await ApiClient.get(_path(fridgeId));
    final raw = jsonDecode(body) as List<dynamic>;
    return raw
        .map((e) => CategoryShelfLife.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 변경분만 전송. 값이 null 이면 override 제거(전역 기본값 복귀).
  /// 반환은 갱신된 12종 머지 결과.
  static Future<List<CategoryShelfLife>> patch(
    String fridgeId,
    Map<String, int?> changes,
  ) async {
    final body = await ApiClient.patchJson(_path(fridgeId), body: changes);
    final raw = jsonDecode(body) as List<dynamic>;
    return raw
        .map((e) => CategoryShelfLife.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 카테고리 → effective 보관일수 맵 (수동 추가 자동입력용).
  static Future<Map<String, int>> effectiveDaysMap(String fridgeId) async {
    final list = await getList(fridgeId);
    return {for (final c in list) c.category: c.days};
  }
}
