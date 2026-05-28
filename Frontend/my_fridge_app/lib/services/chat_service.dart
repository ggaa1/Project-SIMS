import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';

import '../models/chat_message.dart';
import '../repositories/chat_repository.dart';
import 'api_client.dart';

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

  /// chat API 호출.
  /// [onStage] 콜백으로 콜드스타트 안내 메시지를 받을 수 있음.
  static Future<ChatReply> sendChatMessage({
    required String message,
    String? sessionId,
    String? recipeId,
    void Function(String stage)? onStage,
  }) async {
    try {
      final responseBody = await ApiClient.postJson(
        '/chat',
        body: {
          'message': message,
          if (sessionId != null) 'sessionId': sessionId,
          if (recipeId != null) 'recipeId': recipeId,
        },
        onStage: onStage,
      );

      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
      final nextSessionId =
          decoded['sessionId'] as String? ?? decoded['session_id'] as String?;
      final reply = decoded['reply'] as String? ?? '';

      return ChatReply(
        sessionId: nextSessionId ?? sessionId ?? '',
        reply: reply.isEmpty ? '응답 내용이 없습니다.' : reply,
      );
    } catch (_) {
      return ChatReply(
        sessionId:
            sessionId ?? 'local-${DateTime.now().millisecondsSinceEpoch}',
        reply: '응답을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.',
        isFallback: true,
      );
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
