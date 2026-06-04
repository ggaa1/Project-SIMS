import 'dart:convert';
import 'dart:io';

import '../models/ocr_result.dart';
import 'api_client.dart';
import 'ingredient_service.dart';

class OcrService {
  OcrService._();

  static Future<OcrResult> analyzeImage(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw const FileSystemException('이미지 파일을 찾을 수 없습니다.');
    }

    final fileName = imagePath.split(Platform.pathSeparator).last;
    final mimeType = _mimeTypeFor(fileName);

    // 냉장고 override 보관일수를 만료일 산정에 반영하도록 현재 냉장고 ID를 전달.
    // 실패해도 OCR 자체는 진행(서버가 전역 기본값으로 산정).
    String? fridgeId;
    try {
      fridgeId = await IngredientService.currentFridgeId();
    } catch (_) {
      fridgeId = null;
    }

    final responseBody = await ApiClient.postMultipart(
      '/ocr/text',
      fileStream: file.openRead(),
      fileName: fileName,
      mimeType: mimeType,
      fields: fridgeId != null ? {'fridge_id': fridgeId} : null,
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
