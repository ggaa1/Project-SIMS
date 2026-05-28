import 'package:flutter/material.dart';
import '../models/ingredient.dart';
import '../models/recipe.dart';
import '../services/ingredient_service.dart';
import '../services/recipe_service.dart';
import '../theme/app_colors.dart';
import '../widgets/bottom_nav.dart';
import 'ocr_screen.dart';
import 'recipe_detail_screen.dart';

class RecipeScreen extends StatefulWidget {
  const RecipeScreen({super.key});

  @override
  State<RecipeScreen> createState() => _RecipeScreenState();
}

class _RecipeScreenState extends State<RecipeScreen> {
  bool isLoading = false;
  String loadingStage = '추천 받는 중…';
  String? errorMessage;
  List<Ingredient> ingredients = [];
  List<Recipe> recipes = [];

  @override
  void initState() {
    super.initState();
    loadInitialState();
  }

  void _updateStage(String stage) {
    if (!mounted) return;
    setState(() => loadingStage = stage);
  }

  Future<void> loadInitialState() async {
    setState(() {
      isLoading = true;
      loadingStage = '추천 받는 중…';
      errorMessage = null;
    });

    try {
      final loadedIngredients = await IngredientService.getIngredients();
      final loadedRecipes = loadedIngredients.isEmpty
          ? <Recipe>[]
          : await RecipeService.recommendRecipes(onStage: _updateStage);

      if (!mounted) return;

      setState(() {
        ingredients = loadedIngredients;
        recipes = loadedRecipes;
        isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        errorMessage = '추천을 불러오지 못했습니다.';
      });
    }
  }

  Future<void> refreshRecommendations() async {
    setState(() {
      isLoading = true;
      loadingStage = '추천 받는 중…';
      errorMessage = null;
    });

    try {
      final loadedIngredients = await IngredientService.getIngredients();

      if (loadedIngredients.isEmpty) {
        if (!mounted) return;
        setState(() {
          ingredients = loadedIngredients;
          recipes = [];
          isLoading = false;
        });
        return;
      }

      // 사용자가 명시적으로 새로고침 → 캐시 무시
      final recommendedRecipes = await RecipeService.recommendRecipes(
        forceRefresh: true,
        onStage: _updateStage,
      );

      if (!mounted) return;

      setState(() {
        ingredients = loadedIngredients;
        recipes = recommendedRecipes;
        isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        errorMessage = '추천을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.';
      });
    }
  }

  Widget recipeCard(BuildContext context, Recipe recipe) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RecipeDetailScreen(recipe: recipe),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.mainGreen.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.restaurant_menu,
                color: AppColors.mainGreen,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '보유: ${displayList(recipe.ownedIngredients)}',
                    style: const TextStyle(
                      color: AppColors.textSub,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '부족: ${displayList(recipe.missingIngredients)}',
                    style: const TextStyle(
                      color: AppColors.textSub,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              recipe.time,
              style: const TextStyle(
                color: AppColors.deepGreen,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String displayList(List<String> items) {
    if (items.isEmpty) return '없음';
    return items.join(', ');
  }

  Widget ingredientSummary() {
    if (ingredients.isEmpty) {
      return const SizedBox();
    }

    final names = ingredients.take(5).map((item) => item.name).join(', ');
    final extraCount = ingredients.length - 5;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        extraCount > 0 ? '보유 식재료: $names 외 $extraCount개' : '보유 식재료: $names',
        style: const TextStyle(
          color: AppColors.textSub,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget recommendButton() {
    return GestureDetector(
      onTap: isLoading ? null : refreshRecommendations,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: isLoading ? Colors.grey : AppColors.mainGreen,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: isLoading
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      loadingStage,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                )
              : const Text(
                  '보유 식재료로 추천받기',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }

  Widget emptyIngredientView() {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.kitchen_outlined,
                size: 48, color: AppColors.textSub),
            const SizedBox(height: 10),
            const Text(
              '등록된 식재료가 없습니다',
              style: TextStyle(
                color: AppColors.textMain,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '식재료를 먼저 등록하면 추천을 받을 수 있어요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSub, height: 1.4),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const OcrScreen()),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.mainGreen,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '식재료 등록하러 가기',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget errorView() {
    if (errorMessage == null) return const SizedBox();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warningRed.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        errorMessage!,
        style: const TextStyle(
          color: AppColors.warningRed,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget recipeList() {
    if (isLoading && recipes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text(
              loadingStage,
              style: const TextStyle(
                color: AppColors.textSub,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    final body = ingredients.isEmpty
        ? ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.4,
                child: emptyIngredientView(),
              ),
            ],
          )
        : recipes.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 80),
                  Center(
                    child: Text(
                      '추천 결과가 없습니다.',
                      style: TextStyle(color: AppColors.textSub),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: recipes.length,
                itemBuilder: (context, index) {
                  return recipeCard(context, recipes[index]);
                },
              );

    return RefreshIndicator(
      onRefresh: refreshRecommendations,
      child: body,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const BottomNav(currentIndex: 4),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '레시피 추천',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '보유 식재료와 유통기한을 기준으로 추천합니다.',
                style: TextStyle(color: AppColors.textSub),
              ),
              const SizedBox(height: 16),
              ingredientSummary(),
              if (ingredients.isNotEmpty) const SizedBox(height: 12),
              recommendButton(),
              const SizedBox(height: 12),
              errorView(),
              Expanded(child: recipeList()),
            ],
          ),
        ),
      ),
    );
  }
}
