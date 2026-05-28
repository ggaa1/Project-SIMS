import 'package:firebase_auth/firebase_auth.dart';

import '../models/ingredient.dart';
import '../models/user_profile.dart';
import '../repositories/fridge_repository.dart';
import '../repositories/ingredient_repository.dart';
import '../repositories/user_repository.dart';
import 'recipe_service.dart';
import 'storage_service.dart';

/// 식재료 처리 서비스
class IngredientService {
  IngredientService._();

  /// 현재 냉장고 캐시
  static String? _cachedFridgeId;

  /// 현재 냉장고 가져오기
  static Future<String> currentFridgeId() async {
    if (_cachedFridgeId != null) return _cachedFridgeId!;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('로그인이 필요합니다.');

    final profile = await UserRepository.instance.get(uid);
    final primary = profile?.effectivePrimaryFridgeId;
    if (primary != null) {
      _cachedFridgeId = primary;
      return _cachedFridgeId!;
    }

    // 냉장고가 없으면 새로 만든다
    if (profile == null) {
      await UserRepository.instance.createOrUpdate(
        uid: uid,
        email: FirebaseAuth.instance.currentUser?.email ?? '',
      );
    }
    final fridge = await FridgeRepository.instance.create(ownerUid: uid);
    _cachedFridgeId = fridge.id;
    return _cachedFridgeId!;
  }

  /// 캐시 초기화
  static void clearCache() {
    _cachedFridgeId = null;
  }

  static Future<List<Ingredient>> getIngredients() async {
    final fridgeId = await currentFridgeId();
    return IngredientRepository.instance.list(fridgeId);
  }

  /// 실시간 식재료 목록
  static Stream<List<Ingredient>> watchIngredients() async* {
    final fridgeId = await currentFridgeId();
    yield* IngredientRepository.instance.watch(fridgeId);
  }

  /// 유통기한 임박 식재료
  static Future<List<Ingredient>> getExpiringIngredients({
    int withinDays = 7,
  }) async {
    final all = await getIngredients();
    return all.where((item) => item.dday <= withinDays).toList();
  }

  static Stream<List<Ingredient>> watchExpiringIngredients({
    int withinDays = 7,
  }) async* {
    final fridgeId = await currentFridgeId();
    yield* IngredientRepository.instance
        .watchExpiring(fridgeId, withinDays: withinDays);
  }

  /// 식재료 추가
  static Future<Ingredient> addIngredient({
    required String name,
    required String category,
    String? emoji,
    int count = 1,
    required DateTime expireDate,
    String? imageLocalPath,
    String addedVia = IngredientSource.manual,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('로그인이 필요합니다.');
    final fridgeId = await currentFridgeId();

    // 먼저 식재료 저장
    var ingredient = await IngredientRepository.instance.add(
      fridgeId: fridgeId,
      name: name,
      category: category,
      emoji: emoji,
      count: count,
      expireDate: expireDate,
      imageURL: null,
      addedBy: uid,
      addedVia: addedVia,
    );

    // 사진이 있으면 업로드
    if (imageLocalPath != null && imageLocalPath.isNotEmpty) {
      final url = await StorageService.uploadIngredientImage(
        fridgeId: fridgeId,
        ingredientId: ingredient.id,
        localFilePath: imageLocalPath,
      );

      // 업로드 후 URL 저장
      if (url != null) {
        await IngredientRepository.instance.update(
          fridgeId: fridgeId,
          ingredientId: ingredient.id,
          imageURL: url,
        );
        ingredient = ingredient.copyWith(imageURL: url);
      }
      // 실패해도 식재료는 유지
    }

    // 식재료 구성이 바뀌었으니 추천 캐시 무효화
    RecipeService.invalidateRecommendCache();

    return ingredient;
  }

  static Future<Ingredient> updateIngredient(
    Ingredient ingredient, {
    String? imageLocalPath,
  }) async {
    var imageURL = ingredient.imageURL;

    if (imageLocalPath != null && imageLocalPath.isNotEmpty) {
      final uploadedUrl = await StorageService.uploadIngredientImage(
        fridgeId: ingredient.fridgeId,
        ingredientId: ingredient.id,
        localFilePath: imageLocalPath,
      );
      imageURL = uploadedUrl ?? ingredient.imageURL;
    }

    await IngredientRepository.instance.update(
      fridgeId: ingredient.fridgeId,
      ingredientId: ingredient.id,
      name: ingredient.name,
      category: ingredient.category,
      emoji: ingredient.emoji,
      count: ingredient.count,
      expireDate: ingredient.expireDate,
      imageURL: imageURL,
    );

    // 식재료 구성이 바뀌었으니 추천 캐시 무효화
    RecipeService.invalidateRecommendCache();

    return ingredient.copyWith(imageURL: imageURL);
  }

  /// 식재료 삭제
  static Future<void> deleteIngredient(String id) async {
    final fridgeId = await currentFridgeId();
    await IngredientRepository.instance
        .delete(fridgeId: fridgeId, ingredientId: id);
    // 사진도 같이 삭제
    await StorageService.deleteIngredientImage(
      fridgeId: fridgeId,
      ingredientId: id,
    );
    // 식재료 구성이 바뀌었으니 추천 캐시 무효화
    RecipeService.invalidateRecommendCache();
  }

  /// 식재료 검색
  static Future<Ingredient?> searchIngredient(String keyword) async {
    if (keyword.isEmpty) return null;
    final fridgeId = await currentFridgeId();
    final results = await IngredientRepository.instance.searchByName(
      fridgeId: fridgeId,
      keyword: keyword,
    );
    return results.isEmpty ? null : results.first;
  }
}
