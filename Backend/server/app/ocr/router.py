"""이미지 처리 엔드포인트 (Gemini 단일 호출).

원본은 Backend/ocr/router.py. 서버 통합 시 auth 의존성만 app.auth 로 교체.
프론트엔드는 이 엔드포인트(`POST /ocr/text`)로 multipart 이미지 업로드 → 추출된
items 리스트를 사용자 확인 후 /fridges/{fid}/ingredients 로 일괄 등록하는 흐름.
"""
from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Literal, Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from google.genai.errors import APIError as GeminiAPIError
from PIL import UnidentifiedImageError
from pydantic import BaseModel, Field, ValidationError

from app import db
from app.auth import CurrentUser, get_current_user
from app.ocr.preprocess import preprocess_common
from app.ocr.service import process_image
from app.services import shelf_life


router = APIRouter(prefix="/ocr", tags=["ocr"])


def _load_fridge_for_member(fridge_id: str, uid: str) -> Dict[str, Any]:
    """fridge_id 가 주어지면 존재+멤버 확인 후 fridge dict 반환(override 적용용)."""
    snap = db.fridges_col().document(fridge_id).get()
    if not snap.exists:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Fridge not found")
    data = snap.to_dict() or {}
    if uid not in (data.get("memberUids") or []):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="이 냉장고의 멤버가 아닙니다.",
        )
    return data


_ALLOWED_TYPES = {
    "image/jpeg",
    "image/jpg",
    "image/png",
    "image/webp",
    "image/heic",
    "image/heif",
}
_MAX_BYTES = 10 * 1024 * 1024  # 10MB


class OcrResultItem(BaseModel):
    """OCR 추출 결과 1건 + 서버 산정 추천 만료일.

    expire_date 는 카테고리 표준 보관일수(냉장고 override 반영) × coefficient 로
    server 가 계산한 추천값. 사용자가 확인 화면에서 수정 후 저장한다.
    """

    category: str
    name: str
    quantity: str
    coefficient: float = Field(description="유통기한 계수(OCR 산출). 참고용.")
    expire_date: datetime = Field(description="서버 산정 추천 만료일 (KST 날짜의 UTC).")


class OcrTextResponse(BaseModel):
    source_kind: Literal["receipt", "object"] = Field(
        description='이미지 분류 결과. "receipt" 면 영수증, "object" 면 실물 사진(식재료/제품).',
        examples=["receipt"],
    )
    items: List[OcrResultItem] = Field(
        description=(
            "추출된 식재료/품목 목록. {category, name, quantity, coefficient, expire_date}. "
            "expire_date 는 server 가 카테고리 표준 보관일수×계수로 산정한 추천 만료일. "
            "frontend 는 이 리스트를 사용자에게 보여주고 수정/확정받는 UX 권장."
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
    fridge_id: Optional[str] = Form(
        None,
        description="대상 냉장고 ID. 주면 해당 냉장고의 override 보관일수를 만료일 산정에 반영.",
    ),
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

    # 냉장고 override 적용용. fridge_id 없으면 전역 기본값만으로 산정.
    fridge_data: Optional[Dict[str, Any]] = None
    if fridge_id:
        fridge_data = _load_fridge_for_member(fridge_id, user.uid)

    now = db.utcnow()
    items = [
        OcrResultItem(
            category=item.category,
            name=item.name,
            quantity=item.quantity,
            coefficient=item.coefficient,
            expire_date=shelf_life.compute_expire_date(
                item.category, item.coefficient, fridge_data, now,
            ),
        )
        for item in result.items
    ]

    return OcrTextResponse(
        source_kind=result.source_kind,
        items=items,
        model=result.model,
    )
