"""이미지 처리 엔드포인트 (Gemini 단일 호출).

원본은 Backend/ocr/router.py. 서버 통합 시 auth 의존성만 app.auth 로 교체.
프론트엔드는 이 엔드포인트(`POST /ocr/text`)로 multipart 이미지 업로드 → 추출된
items 리스트를 사용자 확인 후 /fridges/{fid}/ingredients 로 일괄 등록하는 흐름.
"""
from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from google.genai.errors import APIError as GeminiAPIError
from PIL import UnidentifiedImageError
from pydantic import BaseModel, Field, ValidationError

from app.auth import CurrentUser, get_current_user
from app.ocr.gemini import Item
from app.ocr.preprocess import preprocess_common
from app.ocr.service import process_image


router = APIRouter(prefix="/ocr", tags=["ocr"])


_ALLOWED_TYPES = {
    "image/jpeg",
    "image/jpg",
    "image/png",
    "image/webp",
    "image/heic",
    "image/heif",
}
_MAX_BYTES = 10 * 1024 * 1024  # 10MB


class OcrTextResponse(BaseModel):
    source_kind: Literal["receipt", "object"] = Field(
        description='이미지 분류 결과. "receipt" 면 영수증, "object" 면 실물 사진(식재료/제품).',
        examples=["receipt"],
    )
    items: list[Item] = Field(
        description=(
            "추출된 식재료/품목 목록. 양쪽 분기 모두 동일 스키마 — {category, name, quantity}. "
            "frontend 는 사용자에게 이 리스트를 보여주고 수정/확정받는 UX 권장."
        ),
    )
    model: str = Field(
        description="응답 생성에 사용된 Gemini 모델 식별자. 디버깅/감사용.",
        examples=["gemini-3.1-flash-lite"],
    )


@router.post(
    "/text",
    response_model=OcrTextResponse,
    summary="이미지 → 식재료 항목 추출 (Gemini Vision)",
    description=(
        "이미지를 Gemini Vision에 1회 호출하여 영수증·실물 사진을 동시에 분류·추출합니다.\n\n"
        "**Branch:**\n"
        "- 영수증(receipt): 각 품목 라인을 items 로 추출. 바코드·합계·매장정보 등 비-품목 텍스트는 응답에서 제거됨.\n"
        "- 실물 사진(object): 보이는 식재료를 items 로 추출. 비식품(생활용품·포장재)은 무시.\n\n"
        "**카테고리(12종 enum):** 야채, 과일, 육류, 수산물, 유제품, 달걀, 곡물/면, 조미료/소스, 음료, 냉동식품, 간식/과자, 기타.\n"
        "**Quantity:** digits-only 문자열 ('1', '2', '12')."
    ),
    responses={
        400: {"description": "이미지 디코딩 실패 또는 빈 업로드"},
        413: {"description": f"파일 크기 {_MAX_BYTES} bytes 초과"},
        415: {"description": "지원하지 않는 content_type. jpeg/png/webp/heic/heif 만 허용."},
        502: {"description": "Gemini API 오류 (응답이 schema 위반 또는 5xx)"},
    },
)
async def ocr_text(
    file: UploadFile = File(..., description="처리할 이미지 (jpeg/png/webp/heic/heif, ≤10MB)"),
    user: CurrentUser = Depends(get_current_user),
) -> OcrTextResponse:
    if file.content_type not in _ALLOWED_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"Unsupported content type: {file.content_type}",
        )

    image_bytes = await file.read()
    if len(image_bytes) > _MAX_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"Image larger than {_MAX_BYTES} bytes",
        )
    if not image_bytes:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Empty image upload",
        )

    try:
        image_bytes = preprocess_common(image_bytes)
    except (UnidentifiedImageError, OSError) as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Image could not be decoded: {exc}",
        ) from exc

    try:
        result = await process_image(image_bytes)
    except GeminiAPIError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Gemini API error: {exc}",
        ) from exc
    except ValidationError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Gemini response schema violation: {exc}",
        ) from exc
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Gemini empty/unparseable response: {exc}",
        ) from exc

    return OcrTextResponse(
        source_kind=result.source_kind,
        items=result.items,
        model=result.model,
    )
