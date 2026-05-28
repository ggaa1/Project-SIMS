import 'package:shared_preferences/shared_preferences.dart';

import 'fcm_service.dart';

/// 알림 설정(유통기한 알림 토글) 영구 저장.
/// 토글 ON/OFF 시 FCM 토큰을 등록/해제하고, 앱 시작 시 이 상태를 반영.
class NotificationSettingsService {
  NotificationSettingsService._();

  static const _key = 'notify_expiring_enabled';

  /// 현재 상태(기본값: 켜짐)
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? true;
  }

  /// 상태 저장 + FCM 등록/해제
  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);

    if (enabled) {
      await FcmService.registerForUser();
    } else {
      await FcmService.unregisterForUser();
    }
  }

  /// 로그인 직후 호출: 저장된 설정에 따라 등록 여부 결정
  static Future<void> applyOnLogin() async {
    if (await isEnabled()) {
      await FcmService.registerForUser();
    }
  }
}
