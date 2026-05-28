import 'dart:convert';
import 'dart:io';

import '../models/ocr_result.dart';
import 'api_client.dart';

class OcrService {
  OcrService._();

  static Future<OcrResult> analyzeImage(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw const FileSystemException('이미지 파일을 찾을 수 없습니다.');
    }

    final fileName = imagePath.split(Platform.pathSeparator).last;
    final mimeType = _mimeTypeFor(fileName);

    final responseBody = await ApiClient.postMultipart(
      '/ocr/text',
      fileStream: file.openRead(),
      fileName: fileName,
      mimeType: mimeType,
    );

    return OcrResult.fromJson(jsonDecode(responseBody) as Map<String, dynamic>);
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
