import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

/// 백엔드 호출용 공용 클라이언트.
/// - HttpClient를 앱 lifecycle 동안 단일 인스턴스로 유지해 TLS handshake/connection
///   재사용 효과를 얻는다. (매 호출마다 new HttpClient + force close 하던 비용 제거)
/// - 콜드스타트 안내용 진행 단계 콜백(onStage) 지원.
class ApiClient {
  ApiClient._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// 글로벌 HttpClient 한 개를 재사용.
  /// idleTimeout 동안 keep-alive 연결 유지. Render 콜드스타트(최대 60s) 대비
  /// connectionTimeout은 길게.
  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 60)
    ..idleTimeout = const Duration(seconds: 90)
    ..maxConnectionsPerHost = 4;

  static Future<String?> _idToken() {
    return FirebaseAuth.instance.currentUser?.getIdToken() ??
        Future.value(null);
  }

  /// 가벼운 헬스 체크. 서버 깨우기 용도(앱 시작 시 백그라운드 호출).
  /// 실패해도 throw 하지 않음.
  static Future<void> warmup() async {
    try {
      final req = await _client
          .getUrl(Uri.parse('$baseUrl/healthz'))
          .timeout(const Duration(seconds: 60));
      final res = await req.close().timeout(const Duration(seconds: 60));
      // 응답 body는 버려도 되지만 stream을 drain 해야 연결이 풀로 돌아간다.
      await res.drain<void>();
    } catch (_) {
      // 워밍업 실패는 무시(실사용 호출에서 다시 시도됨)
    }
  }

  /// JSON POST.
  /// [onStage]가 주어지면 경과 시간에 따라 단계 메시지를 호출자에게 전달한다.
  static Future<String> postJson(
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 60),
    void Function(String stage)? onStage,
    bool requireAuth = true,
  }) {
    return _request(
      method: 'POST',
      path: path,
      body: body,
      timeout: timeout,
      onStage: onStage,
      requireAuth: requireAuth,
    );
  }

  /// JSON GET.
  static Future<String> get(
    String path, {
    Duration timeout = const Duration(seconds: 60),
    void Function(String stage)? onStage,
    bool requireAuth = true,
  }) {
    return _request(
      method: 'GET',
      path: path,
      timeout: timeout,
      onStage: onStage,
      requireAuth: requireAuth,
    );
  }

  /// multipart/form-data 업로드. body는 파일 스트림과 함께 직접 작성.
  /// OCR처럼 큰 페이로드는 별도 헬퍼 대신 이 메서드로 처리.
  static Future<String> postMultipart(
    String path, {
    required Stream<List<int>> fileStream,
    required String fileName,
    required String mimeType,
    String fieldName = 'file',
    Duration timeout = const Duration(seconds: 60),
    bool requireAuth = true,
  }) async {
    final token = requireAuth ? await _idToken() : null;
    if (requireAuth && token == null) {
      throw StateError('Firebase 로그인 토큰을 가져오지 못했습니다.');
    }
    final boundary = '----sims-${DateTime.now().microsecondsSinceEpoch}';

    final request = await _client
        .postUrl(Uri.parse('$baseUrl$path'))
        .timeout(timeout);
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      'multipart/form-data; boundary=$boundary',
    );

    final safeFileName = fileName.replaceAll(RegExp(r'[^\x20-\x7E]'), '_');
    request.add(utf8.encode('--$boundary\r\n'));
    request.add(utf8.encode(
      'Content-Disposition: form-data; name="$fieldName"; filename="$safeFileName"\r\n',
    ));
    request.add(utf8.encode('Content-Type: $mimeType\r\n\r\n'));
    await request.addStream(fileStream);
    request.add(utf8.encode('\r\n--$boundary--\r\n'));

    final response = await request.close().timeout(timeout);
    final responseBody = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}: $responseBody');
    }
    return responseBody;
  }

  static Future<String> _request({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 60),
    void Function(String stage)? onStage,
    required bool requireAuth,
  }) async {
    // 콜드스타트 안내용 진행 타이머
    Timer? t1, t2, t3;
    if (onStage != null) {
      t1 = Timer(const Duration(seconds: 3), () => onStage('잠시만요…'));
      t2 = Timer(const Duration(seconds: 8),
          () => onStage('서버를 깨우는 중이에요 (최대 1분)'));
      t3 = Timer(const Duration(seconds: 25),
          () => onStage('거의 다 됐어요…'));
    }

    try {
      final token = requireAuth ? await _idToken() : null;
      if (requireAuth && token == null) {
        throw StateError('Firebase 로그인 토큰을 가져오지 못했습니다.');
      }

      final request = await _client
          .openUrl(method, Uri.parse('$baseUrl$path'))
          .timeout(timeout);
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      request.headers.contentType =
          ContentType('application', 'json', charset: 'utf-8');
      if (body != null) {
        request.add(utf8.encode(jsonEncode(body)));
      }

      final response = await request.close().timeout(timeout);
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}: $responseBody');
      }
      return responseBody;
    } finally {
      t1?.cancel();
      t2?.cancel();
      t3?.cancel();
    }
  }
}
