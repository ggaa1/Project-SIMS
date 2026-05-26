import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

import '../models/chat_message.dart';
import '../repositories/chat_repository.dart';

class ChatReply {
  final String sessionId;
  final String reply;
  final bool isFallback;

  const ChatReply({
    required this.sessionId,
    required this.reply,
    this.isFallback = false,
  });
}

/// 채팅 처리 서비스
class ChatService {
  ChatService._();

  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// 현재 로그인 사용자의 Firebase ID 토큰. 매 요청마다 새로 받아 만료 자동 처리.
  static Future<String?> _idToken() async {
    return FirebaseAuth.instance.currentUser?.getIdToken();
  }

  /// 새 채팅 시작
  static Future<ChatSession> startSession({
    required String firstUserMessage,
    String? recipeId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('로그인이 필요합니다.');
    return ChatRepository.instance.createSession(
      uid: uid,
      firstUserMessage: firstUserMessage,
      recipeId: recipeId,
    );
  }

  /// 사용자 메시지 저장
  static Future<ChatMessage> sendUserMessage({
    required String sessionId,
    required String text,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('로그인이 필요합니다.');
    return ChatRepository.instance.addMessage(
      uid: uid,
      sessionId: sessionId,
      text: text,
      role: MessageRole.user,
    );
  }

  /// AI 응답 저장
  static Future<ChatMessage> saveAssistantReply({
    required String sessionId,
    required String text,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('로그인이 필요합니다.');
    return ChatRepository.instance.addMessage(
      uid: uid,
      sessionId: sessionId,
      text: text,
      role: MessageRole.assistant,
    );
  }

  /// 메시지 목록
  static Stream<List<ChatMessage>> watchMessages(String sessionId) async* {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      yield [];
      return;
    }
    yield* ChatRepository.instance
        .watchMessages(uid: uid, sessionId: sessionId);
  }

  /// 채팅 목록
  static Stream<List<ChatSession>> watchSessions() async* {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      yield [];
      return;
    }
    yield* ChatRepository.instance.watchSessions(uid);
  }

  static Future<void> deleteSession(String sessionId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await ChatRepository.instance
        .deleteSession(uid: uid, sessionId: sessionId);
  }

  /// chat API 호출
  static Future<ChatReply> sendChatMessage({
    required String message,
    String? sessionId,
    String? recipeId,
  }) async {
    try {
      print('[chat] POST $_baseUrl/chat msg="${message.substring(0, message.length.clamp(0, 30))}..."');
      final response = await _postChat(
        message: message,
        sessionId: sessionId,
        recipeId: recipeId,
      );
      print('[chat] reply OK (session=${response.sessionId})');
      return response;
    } catch (e, st) {
      print('[chat] ERROR: $e');
      print('[chat] stack: $st');
      await Future.delayed(const Duration(milliseconds: 300));
      return ChatReply(
        sessionId: sessionId ?? 'local-${DateTime.now().millisecondsSinceEpoch}',
        reply: 'chat 셰프가 아직 준비 중입니다. 백엔드 연결 후 실제 답변이 표시됩니다.',
        isFallback: true,
      );
    }
  }

  static Future<ChatReply> _postChat({
    required String message,
    String? sessionId,
    String? recipeId,
  }) async {
    final client = HttpClient();
    // Render 콜드스타트 대비 + emulator 환경의 첫 TLS 핸드셰이크 여유
    client.connectionTimeout = const Duration(seconds: 60);

    try {
      final token = await _idToken();
      if (token == null) {
        throw StateError('Firebase 로그인 토큰을 가져오지 못했습니다.');
      }
      final request = await client.postUrl(Uri.parse('$_baseUrl/chat'));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.contentType =
          ContentType('application', 'json', charset: 'utf-8');
      // HttpClient.write는 기본 latin1 — 한글 깨짐. UTF-8 바이트로 직접 add.
      request.add(utf8.encode(jsonEncode({
        'message': message,
        if (sessionId != null) 'sessionId': sessionId,
        if (recipeId != null) 'recipeId': recipeId,
      })));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      print('[chat] HTTP ${response.statusCode} body=${responseBody.substring(0, responseBody.length.clamp(0, 200))}');

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}: $responseBody');
      }

      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
      final nextSessionId =
          decoded['sessionId'] as String? ?? decoded['session_id'] as String?;
      final reply = decoded['reply'] as String? ?? '';

      return ChatReply(
        sessionId: nextSessionId ?? sessionId ?? '',
        reply: reply.isEmpty ? '응답 내용이 없습니다.' : reply,
      );
    } finally {
      client.close(force: true);
    }
  }

  @Deprecated('sendChatMessage를 사용하세요.')
  static Future<ChatMessage> sendMessage(String message) async {
    final response = await sendChatMessage(message: message);
    await Future.delayed(const Duration(milliseconds: 300));
    return ChatMessage(
      id: 'tmp',
      text: response.reply,
      role: MessageRole.assistant,
      createdAt: DateTime.now(),
    );
  }
}
