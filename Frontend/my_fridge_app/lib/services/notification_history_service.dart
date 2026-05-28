import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_record.dart';

/// 푸시 알림 히스토리(최근 N개)를 로컬에 저장/조회.
/// 기본 50개 유지, 그 이상은 오래된 것부터 제거.
class NotificationHistoryService {
  NotificationHistoryService._();

  static const _key = 'notification_history';
  static const _maxRecords = 50;

  static Future<List<NotificationRecord>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => NotificationRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> add(NotificationRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await all();
    // 최신이 앞으로
    current.insert(0, record);
    if (current.length > _maxRecords) {
      current.removeRange(_maxRecords, current.length);
    }
    await prefs.setString(
      _key,
      jsonEncode(current.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
