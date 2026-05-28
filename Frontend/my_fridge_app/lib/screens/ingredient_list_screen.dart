import 'dart:io';
import 'package:flutter/material.dart';
import '../models/ingredient.dart';
import '../services/fridge_service.dart';
import '../services/ingredient_service.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import '../widgets/bottom_nav.dart';
import 'ingredient_detail_screen.dart';

class IngredientListScreen extends StatefulWidget {
  /// 진입 시 검색어로 사전 필터링 (홈 검색 등)
  final String? initialKeyword;

  const IngredientListScreen({super.key, this.initialKeyword});

  @override
  State<IngredientListScreen> createState() => _IngredientListScreenState();
}

class _IngredientListScreenState extends State<IngredientListScreen> {
  Future<List<Ingredient>>? ingredientFuture;

  // 냉장고 상태
  List<FridgeView> myFridges = [];
  String? currentFridgeId;
  bool loadingFridges = true;

  // 검색
  final searchController = TextEditingController();
  String searchKeyword = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialKeyword != null && widget.initialKeyword!.isNotEmpty) {
      searchKeyword = widget.initialKeyword!.trim();
      searchController.text = searchKeyword;
    }
    bootstrap();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  /// 식재료 불러오기
  Future<void> bootstrap() async {
    final fridges = await FridgeService.myFridges();
    final current = await FridgeService.currentFridgeId();
    if (!mounted) return;
    setState(() {
      myFridges = fridges;
      currentFridgeId = current;
      loadingFridges = false;
      ingredientFuture = IngredientService.getIngredients();
    });
  }

  Future<void> selectFridge(FridgeView view) async {
    if (view.id == currentFridgeId) return;
    await FridgeService.setPrimaryFridge(view.id);
    if (!mounted) return;
    setState(() {
      currentFridgeId = view.id;
      ingredientFuture = IngredientService.getIngredients();
    });
  }

  Color ddayColor(int dday) {
    if (dday <= 2) return AppColors.warningRed;
    if (dday <= 5) return AppColors.orange;
    return AppColors.mainGreen;
  }

  Widget imageView(Ingredient item) {
    final url = item.imageURL;

    if (url == null || url.isEmpty) {
      return Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: AppColors.mainGreen.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            item.emoji ?? '❓',
            style: const TextStyle(fontSize: 24),
          ),
        ),
      );
    }

    final imageProvider = StorageService.isRemoteUrl(url)
        ? NetworkImage(url) as ImageProvider
        : FileImage(File(url));

    return ClipOval(
      child: Image(
        image: imageProvider,
        width: 54,
        height: 54,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: AppColors.mainGreen.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              item.emoji ?? '❓',
              style: const TextStyle(fontSize: 24),
            ),
          ),
        ),
      ),
    );
  }

  Widget categoryChip(String text, bool selected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? AppColors.mainGreen : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: selected ? Colors.white : Colors.black,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Future<void> openDetail(Ingredient item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IngredientDetailScreen(ingredient: item),
      ),
    );

    if (mounted) {
      setState(() {
        ingredientFuture = IngredientService.getIngredients();
      });
    }
  }

  Widget ingredientCard(Ingredient item) {
    return GestureDetector(
      onTap: () => openDetail(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            imageView(item),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.category} · ${item.count}개',
                    style: const TextStyle(
                      color: AppColors.textSub,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              item.ddayLabel,
              style: TextStyle(
                color: ddayColor(item.dday),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 냉장고 제목
  Widget headerTitle() {
    if (loadingFridges) {
      return const Text(
        '식재료 리스트',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      );
    }

    if (myFridges.isEmpty) {
      return const Text(
        '식재료 리스트',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      );
    }

    final current = myFridges.firstWhere(
          (v) => v.id == currentFridgeId,
      orElse: () => myFridges.first,
    );

    if (myFridges.length <= 1) {
      return Text(
        current.displayName,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      );
    }

    return InkWell(
      onTap: showFridgePicker,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                current.displayName,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 26),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const BottomNav(currentIndex: 1),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FutureBuilder<List<Ingredient>>(
            future: ingredientFuture,
            builder: (context, snapshot) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  headerTitle(),
                  const SizedBox(height: 16),
                  searchBar(),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _buildListBody(snapshot),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget searchBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: Colors.grey, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: searchController,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                hintText: '식재료 이름으로 검색',
                hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              style: const TextStyle(fontSize: 14),
              onChanged: (value) {
                setState(() => searchKeyword = value.trim());
              },
            ),
          ),
          if (searchKeyword.isNotEmpty)
            GestureDetector(
              onTap: () {
                searchController.clear();
                setState(() => searchKeyword = '');
              },
              child: const Icon(Icons.close, color: Colors.grey, size: 18),
            ),
        ],
      ),
    );
  }

  Widget _buildListBody(AsyncSnapshot<List<Ingredient>> snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }

    if (snapshot.hasError) {
      return Center(child: Text('오류가 발생했습니다: ${snapshot.error}'));
    }

    final all = snapshot.data ?? [];

    if (all.isEmpty) {
      return const Center(
        child: Text(
          '등록된 식재료가 없습니다.',
          style: TextStyle(color: AppColors.textSub),
        ),
      );
    }

    final keyword = searchKeyword.toLowerCase();
    final filtered = keyword.isEmpty
        ? all
        : all
            .where((item) =>
                item.name.toLowerCase().contains(keyword) ||
                item.category.toLowerCase().contains(keyword))
            .toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          '"$searchKeyword" 검색 결과가 없습니다.',
          style: const TextStyle(color: AppColors.textSub),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          ingredientFuture = IngredientService.getIngredients();
        });
      },
      child: ListView.builder(
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          return ingredientCard(filtered[index]);
        },
      ),
    );
  }
}
