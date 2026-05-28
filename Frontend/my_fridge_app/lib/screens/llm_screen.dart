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
  final ScrollController scrollController = ScrollController();
  String? chatSessionId;
  bool isSending = false;
  String typingStage = '응답 받는 중…';

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
    scrollController.dispose();
    super.dispose();
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> sendMessage() async {
    if (isSending) return;

    final text = controller.text.trim();

    if (text.isEmpty) return;

    setState(() {
      isSending = true;
      typingStage = '응답 받는 중…';
      messages.add(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: text,
        role: MessageRole.user,
        createdAt: DateTime.now(),
      ));
      controller.clear();
    });
    scrollToBottom();

    try {
      // 서버 프롬프트가 보유 식재료를 활용할 수 있도록 메시지에 컨텍스트를 함께 전달.
      final ingredients = await IngredientService.getIngredients();
      final names = ingredients.map((e) => e.name).join(', ');
      final payload = names.isEmpty
          ? text
          : '$text\n\n[현재 냉장고 보유 식재료: $names]';

      final response = await ChatService.sendChatMessage(
        message: payload,
        sessionId: chatSessionId,
        onStage: (stage) {
          if (!mounted) return;
          setState(() => typingStage = stage);
        },
      );

      if (!mounted) return;

      setState(() {
        chatSessionId =
            response.sessionId.isEmpty ? chatSessionId : response.sessionId;
        isSending = false;
        messages.add(
          ChatMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            text: response.reply,
            role: MessageRole.assistant,
            createdAt: DateTime.now(),
          ),
        );
      });
      scrollToBottom();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isSending = false;
        messages.add(
          ChatMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            text: '응답을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.',
            role: MessageRole.assistant,
            createdAt: DateTime.now(),
          ),
        );
      });
      scrollToBottom();
    }
  }

  String _formatTime(DateTime t) {
    final h = t.hour;
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = h < 12 ? '오전' : '오후';
    final hour12 = h % 12 == 0 ? 12 : h % 12;
    return '$ampm $hour12:$m';
  }

  Widget aiAvatar() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.mainGreen,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(
        child: Text('👨‍🍳', style: TextStyle(fontSize: 16)),
      ),
    );
  }

  Widget bubble(ChatMessage message) {
    final isUser = message.isUser;
    final bubbleContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: const BoxConstraints(maxWidth: 260),
      decoration: BoxDecoration(
        color: isUser ? AppColors.mainGreen : const Color(0xFFF4F5F1),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isUser ? 16 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 16),
        ),
      ),
      child: Text(
        message.text,
        style: TextStyle(
          color: isUser ? Colors.white : AppColors.textMain,
          fontSize: 14,
          height: 1.5,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            aiAvatar(),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                bubbleContent,
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    _formatTime(message.createdAt),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSub,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget typingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          aiAvatar(),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF4F5F1),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(4),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: const _TypingDots(),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    typingStage,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSub,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget recipeCard(BuildContext context, Recipe recipe) {
    final owned = recipe.ownedIngredients.join(', ');
    final missing = recipe.missingIngredients.join(', ');
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
          crossAxisAlignment: CrossAxisAlignment.start,
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          recipe.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        recipe.time,
                        style: const TextStyle(
                          color: AppColors.deepGreen,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (owned.isNotEmpty)
                    _recipeInfoLine(
                      label: '보유',
                      value: owned,
                      color: AppColors.mainGreen,
                    ),
                  if (missing.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    _recipeInfoLine(
                      label: '부족',
                      value: missing,
                      color: AppColors.orange,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recipeInfoLine({
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSub,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
      ],
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
              child: Row(
                children: [
                  aiAvatar(),
                  const SizedBox(width: 10),
                  const Text(
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
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  ...messages.map(bubble),
                  if (isSending) typingBubble(),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              color: Colors.white,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      decoration: InputDecoration(
                        hintText: '메시지를 입력하세요',
                        filled: true,
                        fillColor: const Color(0xFFF2F2EF),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
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
                      radius: 22,
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
                          : const Icon(Icons.send, color: Colors.white, size: 20),
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

/// 타이핑 인디케이터: 점 3개가 순차적으로 깜빡임
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // 각 점이 1/3 주기씩 늦게 시작
            final phase = (_controller.value - i * 0.18).clamp(0.0, 1.0);
            final scale = 0.55 + 0.45 * _bump(phase);
            return Padding(
              padding: EdgeInsets.only(right: i < 2 ? 4 : 0),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: AppColors.textSub
                        .withValues(alpha: 0.4 + 0.5 * _bump(phase)),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  /// 0~1 입력에 대해 0.3 근방에서 정점을 갖는 부드러운 진폭
  double _bump(double t) {
    if (t < 0.4) return t / 0.4;
    if (t < 0.8) return 1 - (t - 0.4) / 0.4;
    return 0;
  }
}
