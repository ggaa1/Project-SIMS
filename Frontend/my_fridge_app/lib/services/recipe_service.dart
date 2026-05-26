import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/ingredient.dart';
import '../models/recipe.dart';
import '../repositories/recipe_history_repository.dart';
import 'ingredient_service.dart';

/// 레시피 처리 서비스
class RecipeService {
  RecipeService._();

  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// 현재 로그인 사용자의 Firebase ID 토큰
  static Future<String?> _idToken() async {
    return FirebaseAuth.instance.currentUser?.getIdToken();
  }

  // 더미 레시피 데이터
  static final List<Recipe> _recipes = [
    const Recipe(
      id: '1',
      title: '계란 볶음밥',
      time: '15분',
      description: '달걀을 활용해 간단하게 만들 수 있는 볶음밥입니다.',
      ownedIngredients: ['달걀'],
      missingIngredients: ['밥', '대파'],
      steps: [
        '팬에 기름을 두르고 달걀을 풀어 스크램블을 만듭니다.',
        '밥을 넣고 함께 볶습니다.',
        '간장과 소금으로 간을 맞춥니다.',
        '대파를 넣고 마무리합니다.',
      ],
    ),
    const Recipe(
      id: '2',
      title: '크림 파스타',
      time: '25분',
      description: '우유를 활용해 부드럽게 만들 수 있는 크림 파스타입니다.',
      ownedIngredients: ['우유'],
      missingIngredients: ['파스타면', '베이컨'],
      steps: [
        '파스타면을 삶습니다.',
        '팬에 베이컨과 양파를 볶습니다.',
        '우유를 넣고 끓입니다.',
        '삶은 면을 넣고 소스를 졸입니다.',
      ],
    ),
    const Recipe(
      id: '3',
      title: '버섯 된장찌개',
      time: '20분',
      description: '버섯을 활용한 따뜻한 된장찌개입니다.',
      ownedIngredients: ['양송이버섯'],
      missingIngredients: ['된장', '두부', '애호박'],
      steps: [
        '물에 된장을 풀고 끓입니다.',
        '버섯과 채소를 넣습니다.',
        '두부를 넣고 한 번 더 끓입니다.',
        '간을 맞춘 후 완성합니다.',
      ],
    ),
  ];

  /// 최근 본 레시피
  static Future<List<Recipe>> getRecipes() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];
    final history = await RecipeHistoryRepository.instance.list(uid);
    return history.map((item) => item.recipe).toList();
  }

  /// 레시피 이력 실시간 조회
  static Stream<List<Recipe>> watchRecipes() async* {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      yield [];
      return;
    }
    yield* RecipeHistoryRepository.instance
        .watch(uid)
        .map((items) => items.map((e) => e.recipe).toList());
  }

  /// 레시피 추천
  static Future<List<Recipe>> recommendRecipes({
    int maxResults = 3,
    bool useDummyOnFailure = true,
  }) async {
    final ingredients = await IngredientService.getIngredients();

    if (ingredients.isEmpty) {
      return [];
    }

    try {
      final fridgeId = await IngredientService.currentFridgeId();
      final response = await _request(
        method: 'POST',
        path: '/recipes/recommend',
        body: {
          'fridgeId': fridgeId,
          'maxResults': maxResults,
          'ingredients': ingredients.map(_ingredientToJson).toList(),
        },
      );
      final decoded = jsonDecode(response) as Map<String, dynamic>;
      final recipes = decoded['recipes'] as List<dynamic>? ?? [];

      return recipes
          .map((item) => _recipeFromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      if (!useDummyOnFailure) rethrow;
      // 실패하면 더미 추천 사용
      await Future.delayed(const Duration(milliseconds: 600));
      return _dummyRecommendations(ingredients, maxResults);
    }
  }

  /// 본 레시피 저장
  static Future<void> recordView({
    required Recipe recipe,
    String source = RecipeSource.llm,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await RecipeHistoryRepository.instance.record(
      uid: uid,
      recipe: recipe,
      source: source,
    );
  }

  /// 레시피 검색
  static Future<Recipe?> searchRecipe(String keyword) async {
    if (keyword.isEmpty) return null;
    final recipes = await getRecipes();
    for (final recipe in recipes) {
      if (recipe.title.contains(keyword)) return recipe;
    }
    return null;
  }

  /// ID로 레시피 찾기
  static Future<Recipe?> getRecipeById(String id) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    
    final history = await RecipeHistoryRepository.instance.list(uid);
    for (final item in history) {
      if (item.recipe.id == id) return item.recipe;
    }
    return null;
  }

  // 내부 함수

  static Future<String> _request({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    final client = HttpClient();
    // Render 콜드스타트 대비
    client.connectionTimeout = const Duration(seconds: 60);

    try {
      final token = await _idToken();
      if (token == null) {
        throw StateError('Firebase 로그인 토큰을 가져오지 못했습니다.');
      }
      final request = await client.openUrl(method, Uri.parse('$_baseUrl$path'));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.contentType =
          ContentType('application', 'json', charset: 'utf-8');

      if (body != null) {
        // HttpClient.write는 기본 latin1 — 한글 깨짐. UTF-8 바이트로 직접 add.
        request.add(utf8.encode(jsonEncode(body)));
      }

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(responseBody);
      }

      return responseBody;
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, dynamic> _ingredientToJson(Ingredient ingredient) {
    return {
      'name': ingredient.name,
      'category': ingredient.category,
      'count': ingredient.count,
      'expireDate': ingredient.expireDate.toIso8601String(),
      'dday': ingredient.dday,
    };
  }

  static Recipe _recipeFromJson(Map<String, dynamic> json) {
    return Recipe(
      id: json['id'] as String? ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      title: json['title'] as String? ?? '추천 레시피',
      time: json['time'] as String? ?? '20분',
      description: json['description'] as String? ?? '',
      ownedIngredients: _stringList(json['ownedIngredients']),
      missingIngredients: _stringList(json['missingIngredients']),
      steps: _stringList(json['steps']),
    );
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) return [];
    return value.map((item) => item.toString()).toList();
  }

  static List<Recipe> _dummyRecommendations(
    List<Ingredient> ingredients,
    int maxResults,
  ) {
    final ingredientNames = ingredients.map((item) => item.name).toSet();
    final sortedIngredients = List<Ingredient>.from(ingredients)
      ..sort((a, b) => a.dday.compareTo(b.dday));

    // 가진 재료로 추천
    final recommended = _recipes.where((recipe) {
      return recipe.ownedIngredients.any(ingredientNames.contains);
    }).toList();

    if (recommended.isNotEmpty) {
      return recommended.take(maxResults).toList();
    }

    // 없으면 임시 추천 생성
    final first = sortedIngredients.first;
    return [
      Recipe(
        id: 'dummy_${first.id}',
        title: '${first.name} 활용 간단 요리',
        time: '20분',
        description:
            '${first.name}을 먼저 사용하도록 구성한 임시 추천입니다. LLM API가 연결되면 실제 추천 결과로 교체됩니다.',
        ownedIngredients: [first.name],
        missingIngredients: ['소금', '후추'],
        steps: [
          '${first.name}을 먹기 좋은 크기로 손질합니다.',
          '팬을 예열하고 재료를 넣어 익힙니다.',
          '소금과 후추로 간을 맞춥니다.',
          '그릇에 담아 마무리합니다.',
        ],
      ),
    ];
  }
}
