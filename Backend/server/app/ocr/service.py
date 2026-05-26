"""OCR 서비스 계층 (Gemini 단일 호출 버전).

이미지 1장 → Gemini Vision → 분류 + 추출 → ProcessResult.
영수증/실물 둘 다 items 리스트로 통일된 구조 반환. metadata는 sink 용도라
사용자 응답에 포함하지 않음.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Literal, Optional

from .gemini import Item, call_gemini, get_model


SourceKind = Literal["receipt", "object"]


@dataclass
class ProcessResult:
    source_kind: SourceKind
    items: list[Item]
    model: str


async def process_image(
    image_bytes: bytes,
    prompt: Optional[str] = None,
) -> ProcessResult:
    response = await call_gemini(image_bytes)
    return ProcessResult(
        source_kind=response.kind,
        items=response.items,
        model=get_model(),
    )
