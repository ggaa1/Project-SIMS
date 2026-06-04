import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/notification_settings_service.dart';
import '../theme/app_colors.dart';
import 'category_shelf_life_screen.dart';
import 'login_screen.dart';
import 'share_fridge_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool isNotificationOn = true;
  bool isTogglingNotification = false;

  @override
  void initState() {
    super.initState();
    loadNotificationState();
  }

  Future<void> loadNotificationState() async {
    final enabled = await NotificationSettingsService.isEnabled();
    if (!mounted) return;
    setState(() => isNotificationOn = enabled);
  }

  Future<void> toggleNotification(bool value) async {
    if (isTogglingNotification) return;
    // 낙관적 업데이트
    setState(() {
      isNotificationOn = value;
      isTogglingNotification = true;
    });
    try {
      await NotificationSettingsService.setEnabled(value);
    } catch (_) {
      // 실패 시 롤백
      if (mounted) setState(() => isNotificationOn = !value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('알림 설정 저장에 실패했습니다.')),
        );
      }
    } finally {
      if (mounted) setState(() => isTogglingNotification = false);
    }
  }

  Future<void> logout() async {
    await AuthService.logout();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('설정'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textMain,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '유통기한 알림',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Switch(
                    value: isNotificationOn,
                    activeColor: AppColors.mainGreen,
                    onChanged: isTogglingNotification ? null : toggleNotification,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ShareFridgeScreen(),
                  ),
                );
              },
              child: Container(
                width: double.infinity,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.mainGreen),
                ),
                child: const Center(
                  child: Text(
                    '냉장고 공유',
                    style: TextStyle(
                      color: AppColors.mainGreen,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CategoryShelfLifeScreen(),
                  ),
                );
              },
              child: Container(
                width: double.infinity,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.mainGreen),
                ),
                child: const Center(
                  child: Text(
                    '카테고리별 유통기한 설정',
                    style: TextStyle(
                      color: AppColors.mainGreen,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: logout,
              child: Container(
                width: double.infinity,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.warningRed,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Text(
                    '로그아웃',
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
      ),
    );
  }
}