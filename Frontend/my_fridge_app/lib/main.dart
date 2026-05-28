import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/notification_screen.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/fcm_service.dart';
import 'services/notification_settings_service.dart';

/// 알림 이동용 키
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // FCM 초기화
  await FcmService.initialize();

  // 알림 클릭 시 이동
  FcmService.onNotificationTap = (data) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    Navigator.of(ctx).push(
      MaterialPageRoute(builder: (_) => const NotificationScreen()),
    );
  };

  // 로그인 상태면 저장된 알림 설정에 따라 토큰 등록
  if (AuthService.currentUser != null) {
    NotificationSettingsService.applyOnLogin();
  }

  // 백엔드 콜드스타트 흡수: 백그라운드로 미리 깨움 (실패해도 무시)
  unawaited(ApiClient.warmup());

  runApp(const MyFridgeApp());
}

class MyFridgeApp extends StatelessWidget {
  const MyFridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '냉장고를 부탁해',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFFAFAF7),
        useMaterial3: true,
      ),
      home: FutureBuilder<bool>(
        future: AuthService.checkSavedLogin(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          return snapshot.data == true ? const HomeScreen() : const LoginScreen();
        },
      ),
    );
  }
}