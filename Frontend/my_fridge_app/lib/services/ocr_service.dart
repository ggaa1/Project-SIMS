import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/ocr_result.dart';
import 'api_client.dart';

/// OCR 호출 중 발생할 수 있는 에러의 종류.
/// 화면 단에서 사용자에게 맞춤 메시지를 보여주기 위해 구분.
enum OcrErrorKind {
  fileTooLarge,
  unauthorized,
  unsupportedType,
  serverConfig, // ex) GEMINI_API_KEY 미설정
  serverGemini, // 502, Gemini API 오류
  serverEmpty, // 인식된 항목 0개
  network, // 타임아웃/연결 실패
  unknown,
}

class OcrException implements Exception {
  final OcrErrorKind kind;
  final String message;
  const OcrException(this.kind, this.message);

  @override
  String toString() => 'OcrException($kind): $message';
}

class OcrService {
  OcrService._();

  /// 백엔드와 동일한 한도(10MB). 업로드 전에 미리 거른다.
  static const maxBytes = 10 * 1024 * 1024;

  /// 이미지 분석 호출.
  /// [onStage] 콜백을 주면 콜드스타트/분석 단계 안내를 받는다.
  /// 실패 시 [OcrException]을 던진다.
  static Future<OcrResult> analyzeImage(
    String imagePath, {
    void Function(String stage)? onStage,
  }) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw const OcrException(
        OcrErrorKind.unknown,
        '이미지 파일을 찾을 수 없습니다.',
      );
    }

    final length = await file.length();
    if (length > maxBytes) {
      throw const OcrException(
        OcrErrorKind.fileTooLarge,
        '사진이 너무 큽니다. 조금 더 작은 이미지를 선택해주세요.',
      );
    }

    final fileName = imagePath.split(Platform.pathSeparator).last;
    final mimeType = _mimeTypeFor(fileName);

    try {
      final responseBody = await ApiClient.postMultipart(
        '/ocr/text',
        fileStream: file.openRead(),
        fileName: fileName,
        mimeType: mimeType,
        onStage: onStage,
      );
      return OcrResult.fromJson(jsonDecode(responseBody) as Map<String, dynamic>);
    } on TimeoutException catch (_) {
      throw const OcrException(
        OcrErrorKind.network,
        '서버 응답이 늦어지고 있어요. 다시 시도해주세요.',
      );
    } on SocketException catch (_) {
      throw const OcrException(
        OcrErrorKind.network,
        '인터넷 연결을 확인해주세요.',
      );
    } on HttpException catch (e) {
      throw _classifyHttp(e.message);
    } catch (_) {
      throw const OcrException(
        OcrErrorKind.unknown,
        '이미지 분석에 실패했습니다.',
      );
    }
  }

  /// HttpException 메시지("HTTP 413: ...") → OcrException 분류.
  static OcrException _classifyHttp(String message) {
    final code = _statusCodeFromMessage(message);
    final body = message.toLowerCase();
    switch (code) {
      case 401:
      case 403:
        return const OcrException(
          OcrErrorKind.unauthorized,
          '로그인이 만료되었습니다. 다시 로그인해주세요.',
        );
      case 413:
        return const OcrException(
          OcrErrorKind.fileTooLarge,
          '사진이 너무 큽니다. 다른 이미지를 사용해주세요.',
        );
      case 415:
        return const OcrException(
          OcrErrorKind.unsupportedType,
          '지원하지 않는 이미지 형식입니다.',
        );
      case 502:
        if (body.contains('gemini_api_key')) {
          return const OcrException(
            OcrErrorKind.serverConfig,
            '서버 설정에 문제가 있습니다. 잠시 후 다시 시도해주세요.',
          );
        }
        return const OcrException(
          OcrErrorKind.serverGemini,
          'AI 분석 서버에 일시적인 문제가 있어요. 다시 시도해주세요.',
        );
      default:
        return OcrException(
          OcrErrorKind.unknown,
          '이미지 분석에 실패했습니다. (status: $code)',
        );
    }
  }

  static int _statusCodeFromMessage(String message) {
    final match = RegExp(r'HTTP\s+(\d{3})').firstMatch(message);
    if (match == null) return 0;
    return int.tryParse(match.group(1)!) ?? 0;
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
