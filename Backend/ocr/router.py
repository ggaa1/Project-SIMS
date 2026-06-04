"""이미지 처리 엔드포인트 (Gemini 단일 호출).

업로드된 이미지를 Gemini로 보내 영수증/실물을 동시에 분류·추출한다.
응답 contract 는 frontend 인계용 — items 리스트가 1차 시민, 별도 stringify 없음.
"""
from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from google.genai.errors import APIError as GeminiAPIError
from PIL import UnidentifiedImageError
from pydantic import BaseModel, Field, ValidationError

from .auth import CurrentUser, get_current_user
from .gemini import Item
from .preprocess import preprocess_common
from .service import process_image


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
            "추출된 식재료/품목 목록. 양쪽 분기 모두 동일 스키마 — {category, name, quantity, coefficient}. "
            "coefficient 는 유통기한 계수(기본 1.0) — server 가 expireDate 산정에 사용. "
            "frontend 는 사용자에게 이 리스트를 보여주고 수정/확정받는 UX 권장."
        ),
    )
    model: str = Field(
        description="응답 생성에 사용된 Gemini 모델 식별자. 디버깅/감사용.",
        examples=["gemini-3.1-flash-lite"],
    )


_RESPONSE_EXAMPLE_RECEIPT = {
    "source_kind": "receipt",
    "items": [
        {"category": "육류", "name": "한우 앞다리", "quantity": "1", "coefficient": 0.8},
        {"category": "야채", "name": "새송이버섯", "quantity": "1", "coefficient": 1.0},
        {"category": "음료", "name": "칠성사이다 패트 500ml", "quantity": "1", "coefficient": 1.5},
    ],
    "model": "gemini-3.1-flash-lite",
}

_RESPONSE_EXAMPLE_OBJECT = {
    "source_kind": "object",
    "items": [
        {"category": "과일", "name": "바나나", "quantity": "2", "coefficient": 1.0},
        {"category": "과일", "name": "사과", "quantity": "1", "coefficient": 1.2},
        {"category": "야채", "name": "파프리카", "quantity": "3", "coefficient": 1.0},
    ],
    "model": "gemini-3.1-flash-lite",
}


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
        "유통기한 매핑용 proxy 라 엄밀 분류 아님 — 사용자가 frontend UI 에서 수정하는 게 정상 워크플로우.\n\n"
        "**Quantity:** digits-only 문자열 ('1', '2', '12'). DB 저장 시 float (1.0) 변환은 server 측 책임."
    ),
    responses={
        200: {
            "description": "성공",
            "content": {
                "application/json": {
                    "examples": {
                        "receipt": {"summary": "영수증 사진", "value": _RESPONSE_EXAMPLE_RECEIPT},
                        "object": {"summary": "실물 사진", "value": _RESPONSE_EXAMPLE_OBJECT},
                    }
                }
            },
        },
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
        # Gemini-side 4xx/5xx (capacity, auth, model not found 등 모두 upstream issue 로 502 통합).
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Gemini API error: {exc}",
        ) from exc
    except ValidationError as exc:
        # 응답이 response_schema 어긴 경우 — Gemini 모델 비결정성에서 가끔 발생.
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Gemini response schema violation: {exc}",
        ) from exc
    except RuntimeError as exc:
        # call_gemini 의 명시적 raise (parsed is None 케이스).
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Gemini empty/unparseable response: {exc}",
        ) from exc

    return OcrTextResponse(
        source_kind=result.source_kind,
        items=result.items,
        model=result.model,
    )
