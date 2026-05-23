"""Gemini API 클라이언트 — 영수증/실물 사진 통합 처리.

단일 호출 아키텍처:
- 이미지 → Gemini Vision → response_schema 강제 JSON
- kind 필드로 영수증/실물 분기, 응답은 양쪽 모두 {kind, items[]}
- items 필드 통일: {category, name, quantity}. 가격·매장 정보 등은 추출 대상 아님.

env vars:
- GEMINI_API_KEY (필수)
- GEMINI_MODEL   (기본 gemini-3.1-flash-lite)
"""
from __future__ import annotations

import os
import re
from typing import Literal

from google import genai
from google.genai import types
from pydantic import BaseModel, field_validator


_LEADING_DIGITS = re.compile(r"\d+")


DEFAULT_MODEL = "gemini-3.1-flash-lite"


def get_api_key() -> str:
    key = os.getenv("GEMINI_API_KEY")
    if not key:
        raise RuntimeError("GEMINI_API_KEY 환경변수가 설정되지 않았습니다.")
    return key


def get_model() -> str:
    return os.getenv("GEMINI_MODEL", DEFAULT_MODEL)


# server schema-v1.md 2.8 표준 12종. 변경 시 server enum과 동시 갱신 필수.
Category = Literal[
    "야채",
    "과일",
    "육류",
    "수산물",
    "유제품",
    "달걀",
    "곡물/면",
    "조미료/소스",
    "음료",
    "냉동식품",
    "간식/과자",
    "기타",
]


class Item(BaseModel):
    # NOTE: Field(examples=...) 추가 금지 — 이 모델은 Gemini response_schema 로
    # 그대로 직렬화되며, Gemini Schema 가 examples 키 허용 안 함 (extra_forbidden).
    # API 노출용 description/examples 는 router.py 의 OcrItem 에 둘 것.
    category: Category
    name: str
    quantity: str

    @field_validator("quantity")
    @classmethod
    def _quantity_first_run(cls, v: str) -> str:
        # 첫 digit run만. "1개"→"1", "약간"→"". "1박스에 5개"같은 경우엔 앞쪽(1) 우선.
        if not v:
            return ""
        m = _LEADING_DIGITS.search(v)
        return m.group(0) if m else ""


class OcrResponse(BaseModel):
    """단일 호출 응답. kind 로 분기 (receipt/object).

    metadata 는 영수증의 비-품목 텍스트 흡수용 (바코드·합계·매장정보 등이
    items 로 새지 않도록 막는 sink). required 로 둬서 Gemini가 항상 채우도록
    강제 — Optional 이면 빈 채로 skip 하고 items 에 침범하는 경향 발견됨.
    사용자에게 노출되지 않으며 디버깅·검증용.
    """

    kind: Literal["receipt", "object"]
    items: list[Item]
    metadata: list[str]


_PROMPT = """You receive a single image. Classify and extract structured info as JSON.

[Branch 1] Korean grocery RECEIPT (printed text/POS receipt):
- kind = "receipt"
- items: ONLY actual product lines → {category, name (Korean verbatim), quantity}
- quantity: digits only as string. Examples: "1", "2", "12". NEVER include unit suffix (개, 단, 박스, etc.). "" if not visible.
- metadata: EVERYTHING that is not a product — store name, address, phone, datetime, POS/cashier IDs, card info, totals, tax (면세/과세/부가세), payment, **barcodes (any digit-only string of length 8+)**, headers like "상품명/단가/수량", footer messages, etc. If unsure whether a line is a product, put it in metadata. metadata MUST be a non-empty list for receipts (every Korean receipt has store info / dates / totals — never return empty).
- Concrete anti-pattern: a line like "8801005638654" or "8807500007063" → metadata, NEVER items. If a barcode appears between products, attach it to metadata, do not create a separate item for it.
- Categories (use ONLY these 12 Korean labels): 야채, 과일, 육류, 수산물, 유제품, 달걀, 곡물/면, 조미료/소스, 음료, 냉동식품, 간식/과자, 기타
- Minor OCR typos can be corrected based on grocery context (e.g., "샘칼국수" → "생칼국수"). Preserve unambiguous text verbatim.
- Receipt-specific item rules:
  * 라면, 짜파게티, 국수, 쌀, 시리얼 → 곡물/면
  * 빵, 과자, 젤리, 초콜릿, 쇼콜라(초콜릿 음료가 아닌 한) → 간식/과자
  * 두부, 콩가공품, 생활용품(봉투, 쇼핑백, 세제) → 기타
  * 만두, 냉동피자, 즉석조리 → 냉동식품
  * 오이스터(블레이드/스테이크) → 육류 (호주산 소고기 부위)
  * 커피류 음료(쇼콜라 라떼 등) → 음료

[Branch 2] Real-world PHOTO of food/ingredients/products:
- kind = "object"
- items: each visible food/ingredient → {category, name (Korean), quantity}
- quantity: digits only as string counted from the image. Examples: "1", "2", "5". NEVER include unit suffix (개, 단, 박스, etc.). "" only when truly uncountable.
- Skip non-food items entirely (do not list household goods, utensils, packaging)
- metadata = [] (empty list for object branch — sink not needed)
- name 가능한 한국어 단일 식재료명 (사과, 양파, 브로콜리, 방울토마토 등). 카탈로그 사진처럼 종류가 섞여있으면 종류별로 한 줄씩.

[Strict rules]
- Korean text verbatim (after typo correction for receipts), no translation
- quantity = "" (empty string) when not visible/applicable
- Output JSON only, no commentary
"""


async def call_gemini(image_bytes: bytes, mime_type: str = "image/jpeg") -> OcrResponse:
    """이미지 1장을 Gemini로 보내고 구조화 응답을 받는다."""
    client = genai.Client(api_key=get_api_key())
    response = await client.aio.models.generate_content(
        model=get_model(),
        contents=[
            types.Part.from_bytes(data=image_bytes, mime_type=mime_type),
            _PROMPT,
        ],
        config=types.GenerateContentConfig(
            response_mime_type="application/json",
            response_schema=OcrResponse,
        ),
    )
    parsed = response.parsed
    if parsed is None:
        raise RuntimeError(f"Gemini가 schema-conformant 응답을 만들지 못함. raw={response.text[:500]}")
    return parsed
