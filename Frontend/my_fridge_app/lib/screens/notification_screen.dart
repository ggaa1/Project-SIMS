import 'dart:io';
import 'package:flutter/material.dart';
import '../models/ingredient.dart';
import '../models/notification_record.dart';
import '../services/ingredient_service.dart';
import '../services/notification_history_service.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import '../widgets/bottom_nav.dart';
import 'ocr_screen.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  Future<_NotificationData>? future;

  @override
  void initState() {
    super.initState();
    future = loadAll();
  }

  Future<_NotificationData> loadAll() async {
    final results = await Future.wait([
      IngredientService.getExpiringIngredients(),
      NotificationHistoryService.all(),
    ]);
    return _NotificationData(
      expiring: results[0] as List<Ingredient>,
      history: results[1] as List<NotificationRecord>,
    );
  }

  Future<void> refresh() async {
    setState(() {
      future = loadAll();
    });
    await future;
  }

  Future<void> clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('알림 기록 삭제'),
        content: const Text('받은 알림 기록을 모두 지울까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제',
                style: TextStyle(color: AppColors.warningRed)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await NotificationHistoryService.clear();
    if (!mounted) return;
    refresh();
  }

  Color ddayColor(int dday) {
    if (dday <= 2) return AppColors.warningRed;
    if (dday <= 5) return AppColors.orange;
    return AppColors.mainGreen;
  }

  Widget imageView(Ingredient item) {
    if (item.imageURL == null || item.imageURL!.isEmpty) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.mainGreen.withValues(alpha: 0.15),
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

    final imageProvider = StorageService.isRemoteUrl(item.imageURL)
        ? NetworkImage(item.imageURL!) as ImageProvider
        : FileImage(File(item.imageURL!));

    return ClipOval(
      child: Image(
        image: imageProvider,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.broken_image, size: 20),
        ),
      ),
    );
  }

  String relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
  }

  Widget historyCard(NotificationRecord record) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.mainGreen.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.notifications_active,
                size: 20, color: AppColors.mainGreen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (record.title.isNotEmpty)
                  Text(
                    record.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                if (record.body.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    record.body,
                    style: const TextStyle(
                      color: AppColors.textMain,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  relativeTime(record.receivedAt),
                  style: const TextStyle(
                    color: AppColors.textSub,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget expiringCard(Ingredient item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
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
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  item.ddayDescription,
                  style: const TextStyle(color: AppColors.textSub),
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
    );
  }

  Widget emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.notifications_off_outlined,
                size: 56, color: AppColors.textSub),
            const SizedBox(height: 12),
            const Text(
              '아직 받은 알림이 없습니다',
              style: TextStyle(
                color: AppColors.textMain,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '유통기한이 임박한 식재료가 있으면\n자동으로 알림이 도착합니다.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSub, height: 1.4),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const OcrScreen()),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.mainGreen,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Text(
                  '식재료 등록하기',
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

  Widget sectionLabel(String text, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textMain,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const BottomNav(currentIndex: 2),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FutureBuilder<_NotificationData>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('오류가 발생했습니다: ${snapshot.error}'));
              }

              final data = snapshot.data ??
                  const _NotificationData(expiring: [], history: []);
              final isEmpty = data.expiring.isEmpty && data.history.isEmpty;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '알림',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '받은 알림과 유통기한 임박 식재료를 확인하세요.',
                    style: TextStyle(color: AppColors.textSub),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: refresh,
                      child: isEmpty
                          ? ListView(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              children: [
                                SizedBox(
                                  height: MediaQuery.of(context).size.height *
                                      0.5,
                                  child: emptyState(),
                                ),
                              ],
                            )
                          : ListView(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              children: [
                                if (data.history.isNotEmpty) ...[
                                  sectionLabel(
                                    '받은 알림 (${data.history.length})',
                                    trailing: GestureDetector(
                                      onTap: clearHistory,
                                      child: const Text(
                                        '모두 지우기',
                                        style: TextStyle(
                                          color: AppColors.textSub,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  ...data.history.map(historyCard),
                                  const SizedBox(height: 10),
                                ],
                                if (data.expiring.isNotEmpty) ...[
                                  sectionLabel(
                                      '유통기한 임박 (${data.expiring.length})'),
                                  ...data.expiring.map(expiringCard),
                                ],
                              ],
                            ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NotificationData {
  final List<Ingredient> expiring;
  final List<NotificationRecord> history;

  const _NotificationData({required this.expiring, required this.history});
}
