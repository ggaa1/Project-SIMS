import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

import '../models/ocr_result.dart';

class OcrService {
  OcrService._();

  // OCR이 server와 통합되어 같은 URL 사용. API_BASE_URL 하나로 충분.
  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static Future<String?> _idToken() async {
    return FirebaseAuth.instance.currentUser?.getIdToken();
  }

  static Future<OcrResult> analyzeImage(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw const FileSystemException('이미지 파일을 찾을 수 없습니다.');
    }

    final client = HttpClient();
    // Render 콜드스타트(최대 60s) + Gemini 호출(5~15s) 여유
    client.connectionTimeout = const Duration(seconds: 60);

    try {
      final token = await _idToken();
      if (token == null) {
        throw StateError('Firebase 로그인 토큰을 가져오지 못했습니다.');
      }
      final request = await client.postUrl(Uri.parse('$_baseUrl/ocr/text'));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final boundary = '----sims-${DateTime.now().microsecondsSinceEpoch}';
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );

      final fileName = imagePath.split(Platform.pathSeparator).last;
      final mimeType = _mimeTypeFor(fileName);
      // multipart 헤더는 ASCII만 — request.write 안전. 파일명 한글이면 깨질 수 있으니 ASCII로 안전화.
      final safeFileName = fileName.replaceAll(RegExp(r'[^\x20-\x7E]'), '_');
      request.add(utf8.encode('--$boundary\r\n'));
      request.add(utf8.encode(
        'Content-Disposition: form-data; name="file"; filename="$safeFileName"\r\n',
      ));
      request.add(utf8.encode('Content-Type: $mimeType\r\n\r\n'));
      await request.addStream(file.openRead());
      request.add(utf8.encode('\r\n--$boundary--\r\n'));

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(body);
      }

      return OcrResult.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } finally {
      client.close(force: true);
    }
  }

  static String _mimeTypeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.heif')) return 'image/heif';
    return 'image/jpeg';
  }
}
