import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/notification_record.dart';
import '../repositories/fcm_token_repository.dart';
import 'notification_history_service.dart';

/// 백그라운드 알림 처리
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 백그라운드 알림 로그
  if (kDebugMode) {
    // ignore: avoid_print
    print('[FCM] background message: ${message.messageId}');
  }
}

class FcmService {
  FcmService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();

  /// 알림 채널
  static const _channelId = 'fridge_expiring_channel';
  static const _channelName = '유통기한 알림';
  static const _channelDesc = '식재료 유통기한이 임박했을 때 알림을 보냅니다.';

  static bool _initialized = false;

  /// 알림 클릭 콜백
  static void Function(Map<String, dynamic> data)? onNotificationTap;

  /// FCM 초기화
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // 백그라운드 핸들러 등록
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 로컬 알림 초기화
    await _initLocalNotifications();

    // 포그라운드 알림 표시 설정
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 포그라운드 메시지 처리
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 알림 클릭 처리
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    // 종료 상태 알림 처리
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      _handleMessageOpenedApp(initial);
    }
  }

  static Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        // 로컬 알림 클릭 처리
        final payload = response.payload;
        if (payload != null && onNotificationTap != null) {
          onNotificationTap!({'payload': payload});
        }
      },
    );

    // 알림 채널 생성
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// 알림 토큰 등록
  static Future<void> registerForUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // 권한 요청
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      // 권한 거부 로그
      if (kDebugMode) print('[FCM] 알림 권한 거부됨');
    }

    // 토큰 가져오기
    final token = await _messaging.getToken();
    if (token == null) {
      if (kDebugMode) print('[FCM] 토큰을 받지 못함');
      return;
    }

    final deviceId = await _resolveDeviceId();
    final platform =
    Platform.isIOS ? DevicePlatform.ios : DevicePlatform.android;

    await FcmTokenRepository.instance.register(
      uid: uid,
      deviceId: deviceId,
      token: token,
      platform: platform,
    );

    // 토큰 갱신 처리
    _messaging.onTokenRefresh.listen((newToken) async {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid == null) return;
      await FcmTokenRepository.instance.register(
        uid: currentUid,
        deviceId: deviceId,
        token: newToken,
        platform: platform,
      );
    });

    if (kDebugMode) print('[FCM] 토큰 등록 완료: ${token.substring(0, 20)}...');
  }

  /// 알림 토큰 삭제
  static Future<void> unregisterForUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final deviceId = await _resolveDeviceId();
    await FcmTokenRepository.instance.unregister(uid: uid, deviceId: deviceId);
  }

  /// 임시 디바이스 ID
  static Future<String> _resolveDeviceId() async {
    final token = await _messaging.getToken();
    if (token != null && token.length >= 16) {
      return token.substring(0, 16);
    }
    return 'unknown';
  }

  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    final android = message.notification?.android;

    if (notification == null) return;

    // 히스토리에 저장
    await _recordNotification(message);

    // 앱 사용 중이면 직접 알림 표시
    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: android?.smallIcon ?? '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: message.data.isNotEmpty ? message.data.toString() : null,
    );
  }

  static Future<void> _handleMessageOpenedApp(RemoteMessage message) async {
    if (kDebugMode) print('[FCM] 알림 탭으로 열림: ${message.messageId}');
    // 탭 시점에도 히스토리에 누락 없이 저장
    await _recordNotification(message);
    if (onNotificationTap != null) {
      onNotificationTap!(message.data);
    }
  }

  static Future<void> _recordNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title'] as String? ?? '';
    final body = notification?.body ?? message.data['body'] as String? ?? '';
    if (title.isEmpty && body.isEmpty) return;

    final id = message.messageId ??
        '${DateTime.now().millisecondsSinceEpoch}';
    try {
      await NotificationHistoryService.add(
        NotificationRecord(
          id: id,
          title: title,
          body: body,
          receivedAt: DateTime.now(),
        ),
      );
    } catch (_) {
      // 저장 실패해도 알림 흐름은 계속
    }
  }
}
