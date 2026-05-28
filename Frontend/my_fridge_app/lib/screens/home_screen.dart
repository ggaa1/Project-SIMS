import 'package:flutter/material.dart';
import '../models/ingredient.dart';
import '../models/recipe.dart';
import '../services/fridge_service.dart';
import '../services/ingredient_service.dart';
import '../services/recipe_service.dart';
import '../theme/app_colors.dart';
import '../widgets/bottom_nav.dart';
import 'ingredient_list_screen.dart';
import 'notification_screen.dart';
import 'ocr_screen.dart';
import 'recipe_detail_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final searchController = TextEditingController();
  String searchMessage = '';

  // 냉장고 상태
  List<FridgeView> myFridges = [];
  String? currentFridgeId;
  bool loadingFridges = true;

  // 화면 새로고침용 키
  Key dataKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    loadFridges();
  }

  Future<void> loadFridges() async {
    final list = await FridgeService.myFridges();
    final current = await FridgeService.currentFridgeId();
    if (!mounted) return;
    setState(() {
      myFridges = list;
      currentFridgeId = current;
      loadingFridges = false;
    });
  }

  Future<void> selectFridge(FridgeView view) async {
    if (view.id == currentFridgeId) return;
    await FridgeService.setPrimaryFridge(view.id);
    if (!mounted) return;
    setState(() {
      currentFridgeId = view.id;
      // 냉장고 변경 후 다시 불러오기
      dataKey = UniqueKey();
    });
  }

  Future<void> search() async {
    final keyword = searchController.text.trim();

    if (keyword.isEmpty) return;

    final ingredient = await IngredientService.searchIngredient(keyword);

    if (!mounted) return;

    if (ingredient != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => IngredientListScreen(initialKeyword: keyword),
        ),
      );
      // 결과 화면 이동 후 입력 초기화
      searchController.clear();
      return;
    }

    final recipe = await RecipeService.searchRecipe(keyword);

    if (!mounted) return;

    if (recipe != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RecipeDetailScreen(recipe: recipe),
        ),
      );
      return;
    }

    setState(() {
      searchMessage = '해당 식재료 또는 레시피가 없습니다';
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          searchMessage = '';
        });
      }
    });
  }

  /// 냉장고 제목
  Widget fridgeHeader() {
    const baseStyle = TextStyle(
      color: AppColors.textSub,
      fontWeight: FontWeight.bold,
    );

    if (loadingFridges) {
      return const Text('', style: baseStyle);
    }

    if (myFridges.isEmpty) {
      return const Text('냉장고', style: baseStyle);
    }

    final current = myFridges.firstWhere(
          (v) => v.id == currentFridgeId,
      orElse: () => myFridges.first,
    );

    if (myFridges.length <= 1) {
      return Text(current.displayName, style: baseStyle);
    }

    return InkWell(
      onTap: showFridgePicker,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                current.displayName,
                style: baseStyle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.expand_more,
              size: 18,
              color: AppColors.textSub,
            ),
          ],
        ),
      ),
    );
  }

  void showFridgePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '냉장고 선택',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ...myFridges.map((view) {
                  final selected = view.id == currentFridgeId;
                  return InkWell(
                    onTap: () {
                      Navigator.pop(sheetContext);
                      selectFridge(view);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.mainGreen.withValues(alpha: 0.1)
                            : const Color(0xFFF5F5F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? AppColors.mainGreen
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: selected
                                ? AppColors.mainGreen
                                : AppColors.textSub,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  view.displayName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: selected
                                        ? AppColors.deepGreen
                                        : AppColors.textMain,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${view.memberCount}명 사용 중',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSub,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Color ddayColor(int dday) {
    if (dday < 0) return AppColors.warningRed;
    if (dday <= 1) return AppColors.warningRed;
    if (dday <= 3) return AppColors.orange;
    return AppColors.mainGreen;
  }

  Widget expiringCard(List<Ingredient> items) {
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.mainGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.check_circle_outline,
                  color: AppColors.mainGreen),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                '임박한 식재료가 없어요',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textMain,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 임박순 정렬(D-day 작은 순) + 상위 3개
    final sorted = [...items]..sort((a, b) => a.dday.compareTo(b.dday));
    final top = sorted.take(3).toList();
    final extra = sorted.length - top.length;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NotificationScreen()),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            for (int i = 0; i < top.length; i++) ...[
              _expiringRow(top[i]),
              if (i < top.length - 1)
                const Divider(height: 1, color: Color(0xFFEFEFEF)),
            ],
            if (extra > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '외 $extra개 더 보기',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSub,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_right,
                        size: 16, color: AppColors.textSub),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _expiringRow(Ingredient item) {
    final color = ddayColor(item.dday);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                item.emoji ?? '🍽',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.count}개',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSub,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              item.ddayLabel,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget recipeCard(Recipe recipe) {
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
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.mainGreen,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.restaurant_menu,
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '오늘의 추천',
                    style: TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    recipe.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              children: [
                const Icon(Icons.schedule,
                    color: Colors.white, size: 14),
                const SizedBox(width: 4),
                Text(
                  recipe.time,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const BottomNav(currentIndex: 2),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await loadFridges();
            if (!mounted) return;
            setState(() {
              dataKey = UniqueKey();
            });
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '냉장고를 부탁해',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textMain,
                    ),
                  ),
                  Row(
                    children: [
                      FutureBuilder(
                        key: ValueKey('badge-$dataKey'),
                        future: IngredientService.getExpiringIngredients(),
                        builder: (context, snapshot) {
                          final notificationCount = snapshot.data?.length ?? 0;

                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const NotificationScreen(),
                                ),
                              );
                            },
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                const Icon(Icons.notifications_none, size: 26),
                                if (notificationCount > 0)
                                  Positioned(
                                    right: -6,
                                    top: -6,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        '$notificationCount',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SettingsScreen(),
                            ),
                          );
                        },
                        child: const Icon(Icons.settings, size: 24),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              fridgeHeader(),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: TextField(
                        controller: searchController,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          icon: Icon(Icons.search, color: Colors.grey),
                          hintText: '식재료 또는 레시피 검색',
                          hintStyle: TextStyle(color: Colors.grey),
                        ),
                        onSubmitted: (_) => search(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: search,
                    child: Container(
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppColors.mainGreen,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: Text(
                          '검색',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (searchMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    searchMessage,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 25),
              const Text(
                '유통기한 임박',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<Ingredient>>(
                key: ValueKey('expiring-$dataKey'),
                future: IngredientService.getExpiringIngredients(),
                builder: (context, snapshot) {
                  final items = snapshot.data ?? [];
                  return expiringCard(items);
                },
              ),
              const SizedBox(height: 25),
              const Text(
                '추천 레시피',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<Recipe>>(
                key: ValueKey('recipe-$dataKey'),
                future: RecipeService.recommendRecipes(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return const Text(
                      '추천 레시피를 불러오지 못했습니다.',
                      style: TextStyle(color: AppColors.textSub),
                    );
                  }

                  final recipes = snapshot.data ?? [];

                  if (recipes.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '식재료를 등록하면 추천 레시피가 표시됩니다.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSub),
                          ),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const OcrScreen(),
                                ),
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
                    );
                  }

                  return Column(
                    children: recipes.take(2).map(recipeCard).toList(),
                  );
                },
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
