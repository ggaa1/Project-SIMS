import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../models/recipe.dart';
import '../services/chat_service.dart';
import '../services/ingredient_service.dart';
import '../services/recipe_service.dart';
import '../theme/app_colors.dart';
import '../widgets/bottom_nav.dart';
import 'recipe_detail_screen.dart';

class LlmScreen extends StatefulWidget {
  const LlmScreen({super.key});

  @override
  State<LlmScreen> createState() => _LlmScreenState();
}

class _LlmScreenState extends State<LlmScreen> {
  final TextEditingController controller = TextEditingController();
  String? chatSessionId;
  bool isSending = false;

  final List<ChatMessage> messages = [
    ChatMessage(
      id: 'welcome',
      text: '안녕하세요! 냉장고에 있는 식재료를 바탕으로 레시피를 추천해드릴게요.',
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
    ),
  ];

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> sendMessage() async {
    if (isSending) return;

    final text = controller.text.trim();

    if (text.isEmpty) return;

    setState(() {
      isSending = true;
      messages.add(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: text,
        role: MessageRole.user,
        createdAt: DateTime.now(),
      ));
      controller.clear();
    });

    try {
      final ingredients = await IngredientService.getIngredients();
      final response = await ChatService.sendChatMessage(
        message: text,
        sessionId: chatSessionId,
      );

      if (!mounted) return;

      setState(() {
        chatSessionId =
            response.sessionId.isEmpty ? chatSessionId : response.sessionId;
        isSending = false;
        messages.add(
          ChatMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            text:
                '${response.reply}\n\n현재 보유 식재료: ${ingredients.map((e) => e.name).join(', ')}',
            role: MessageRole.assistant,
            createdAt: DateTime.now(),
          ),
        );
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isSending = false;
        messages.add(
          ChatMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            text: 'chat 셰프 응답을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.',
            role: MessageRole.assistant,
            createdAt: DateTime.now(),
          ),
        );
      });
    }
  }

  Widget bubble(ChatMessage message) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 285),
        decoration: BoxDecoration(
          color: message.isUser ? AppColors.mainGreen : Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: message.isUser ? Colors.white : AppColors.textMain,
            height: 1.4,
          ),
        ),
      ),
    );
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
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF1EFE8)),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.mainGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
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
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '보유: ${recipe.ownedIngredients.join(', ')}',
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

  Widget recommendedRecipes() {
    return FutureBuilder<List<Recipe>>(
      future: RecipeService.getRecipes(),
      builder: (context, snapshot) {
        final recipes = snapshot.data ?? [];

        if (recipes.isEmpty) {
          return const SizedBox();
        }

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F8F6),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AI 추천 레시피',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              ...recipes.take(2).map((recipe) => recipeCard(context, recipe)),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const BottomNav(currentIndex: 3),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: const Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.mainGreen,
                    child: Text('👨‍🍳'),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'AI 셰프',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            recommendedRecipes(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: messages.map(bubble).toList(),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        hintText: '요리 중 궁금한 점을 입력하세요',
                        filled: true,
                        fillColor: Colors.grey.shade200,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: isSending ? null : sendMessage,
                    child: CircleAvatar(
                      backgroundColor:
                          isSending ? Colors.grey : AppColors.mainGreen,
                      child: isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
