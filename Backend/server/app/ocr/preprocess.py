"""Vision LLM 호출 전 이미지 전처리.

토큰 수와 네트워크 비용을 줄이는 가장 큰 레버는 resize. EXIF 회전 보정은
스마트폰 사진의 잘못된 방향 문제를 막기 위해 필수. JPEG quality는 OCR
정확도와 직결되므로 압축 손실 최소화 쪽으로 보수적으로 잡는다.
"""
from __future__ import annotations

import io

from PIL import Image, ImageOps


_DEFAULT_MAX_EDGE = 1536
_JPEG_QUALITY = 92


def preprocess_common(
    image_bytes: bytes,
    max_edge: int = _DEFAULT_MAX_EDGE,
) -> bytes:
    img = Image.open(io.BytesIO(image_bytes))
    img = ImageOps.exif_transpose(img)
    img.thumbnail((max_edge, max_edge))
    img = img.convert("RGB")

    out = io.BytesIO()
    img.save(out, "JPEG", quality=_JPEG_QUALITY, optimize=True)
    return out.getvalue()
