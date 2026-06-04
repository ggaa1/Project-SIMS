"""카테고리별 표준 유통기한(보관일수) 산정.

`Backend/ocr/docs/expiry-spec-v1.md` (v2.1) 구현.

핵심:
- 2계층 기본값: 냉장고 override > 전역 appConfig.defaults > 서버 하드코딩 상수(최후 폴백)
- expireDate = KST 오늘 날짜 + round(effective(category) × coefficient)일, [1, 3650] 클램프
- coefficient 는 [0.1, 10] 클램프, 비정상(음수/0/NaN/inf/비숫자)은 1.0 (계수로 인한 거부 없음)
- 전역 기본값은 12종 결손 금지(시드 + 누락 키 메움으로 보장)
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional

from app import db

# 카테고리 12종 (schema-v1.md 2.8 / expiry-spec-v1.md §3)
CATEGORIES = [
    "야채", "과일", "육류", "수산물", "유제품", "달걀",
    "곡물/면", "조미료/소스", "음료", "냉동식품", "간식/과자", "기타",
]

# 서버 하드코딩 최후 폴백 (expiry-spec-v1.md §3 표).
# 전역 appConfig 문서가 누락/손상된 비상 상황에만 도달. 평상시엔 쓰이지 않음.
SERVER_HARDCODED_DEFAULTS: Dict[str, int] = {
    "야채": 7, "과일": 7, "육류": 3, "수산물": 2,
    "유제품": 14, "달걀": 30, "곡물/면": 180, "조미료/소스": 180,
    "음료": 90, "냉동식품": 180, "간식/과자": 120, "기타": 7,
}

MIN_DAYS = 1
MAX_DAYS = 3650
MIN_COEF = 0.1
MAX_COEF = 10.0
DEFAULT_COEF = 1.0

# KST(UTC+9) — 일수 가산은 KST 캘린더 날짜 기준 (프론트 D-day 표시와 일치).
KST = timezone(timedelta(hours=9))

_APP_CONFIG_DOC = "categoryShelfLife"


def _is_number(v: Any) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def clamp_days(days: int) -> int:
    return max(MIN_DAYS, min(MAX_DAYS, int(days)))


def sanitize_coefficient(value: Any) -> float:
    """계수 보정: 비숫자/NaN/inf/0이하 → 1.0, 범위 밖 → [0.1, 10] 클램프."""
    try:
        f = float(value)
    except (TypeError, ValueError):
        return DEFAULT_COEF
    if f != f or f in (float("inf"), float("-inf")) or f <= 0:
        return DEFAULT_COEF
    return min(MAX_COEF, max(MIN_COEF, f))


def get_global_defaults() -> Dict[str, int]:
    """전역 기본값 12종.

    appConfig/categoryShelfLife.defaults 를 읽고, 누락/비정상 키는 서버 하드코딩
    상수로 메워 **항상 12종 완비**를 보장한다. 문서 접근 실패 시에도 상수로 동작.
    """
    merged = dict(SERVER_HARDCODED_DEFAULTS)
    try:
        snap = db.app_config_col().document(_APP_CONFIG_DOC).get()
        if snap.exists:
            stored = (snap.to_dict() or {}).get("defaults") or {}
            for cat in CATEGORIES:
                v = stored.get(cat)
                if _is_number(v):
                    merged[cat] = clamp_days(int(v))
    except Exception:
        # 전역 문서 접근 실패 → 하드코딩 상수로 폴백 (최후 방어선).
        pass
    return merged


def effective_map(fridge_data: Optional[Dict[str, Any]]) -> Dict[str, int]:
    """냉장고 override 를 전역 기본값 위에 머지한 12종 유효 보관일수."""
    result = get_global_defaults()
    override = (fridge_data or {}).get("categoryShelfLife") or {}
    for cat in CATEGORIES:
        v = override.get(cat)
        if _is_number(v):
            result[cat] = clamp_days(int(v))
    return result


def effective_days(category: str, fridge_data: Optional[Dict[str, Any]]) -> int:
    """단일 카테고리 유효 보관일수. 미지의 카테고리는 '기타'로 폴백."""
    emap = effective_map(fridge_data)
    return emap.get(category) or emap.get("기타") or SERVER_HARDCODED_DEFAULTS["기타"]


def _round_half_up(x: float) -> int:
    # 파이썬 round()는 banker's rounding → 0.5는 올림으로 통일 (spec §1).
    # days×coef는 항상 양수이므로 +0.5 후 절단이면 충분.
    return int(x + 0.5)


def compute_expire_date(
    category: str,
    coefficient: Any,
    fridge_data: Optional[Dict[str, Any]],
    now_utc: Optional[datetime] = None,
) -> datetime:
    """expireDate 산정.

    `expireDate = KST_today + round(effective(category) × coefficient)일`, [1, 3650] 클램프.
    반환은 **KST 자정의 UTC 환산** datetime (Firestore Timestamp 저장용).
    """
    if now_utc is None:
        now_utc = db.utcnow()
    coef = sanitize_coefficient(coefficient)
    days = effective_days(category, fridge_data)
    total = clamp_days(_round_half_up(days * coef))

    kst_today = now_utc.astimezone(KST).date()
    expire_kst = datetime(
        kst_today.year, kst_today.month, kst_today.day, tzinfo=KST
    ) + timedelta(days=total)
    return expire_kst.astimezone(timezone.utc)


def merged_list(fridge_data: Optional[Dict[str, Any]]) -> list[dict]:
    """GET /category-shelf-life 응답용. 12종 전체 + override 여부(isCustom)."""
    globals_ = get_global_defaults()
    override = (fridge_data or {}).get("categoryShelfLife") or {}
    out = []
    for cat in CATEGORIES:
        is_custom = _is_number(override.get(cat))
        days = clamp_days(int(override[cat])) if is_custom else globals_[cat]
        # 필드명(snake)으로 반환 → CategoryShelfLifeItem(**row) 가 alias 설정과 무관하게 안전.
        # JSON 응답은 FastAPI 가 alias(camelCase)로 직렬화한다(isCustom).
        out.append({"category": cat, "days": days, "is_custom": is_custom})
    return out


def seed_global_defaults(overwrite_existing: bool = False) -> Dict[str, int]:
    """appConfig/categoryShelfLife 시드 (idempotent).

    - 문서 없음 → SERVER_HARDCODED_DEFAULTS 로 생성.
    - 문서 있음 → 누락 카테고리 키만 채우고 기존 운영값은 보존(merge).
    - overwrite_existing=True → 12종 전부 하드코딩 상수로 갱신(운영자 명시 의도).
    """
    ref = db.app_config_col().document(_APP_CONFIG_DOC)
    snap = ref.get()
    now = db.utcnow()

    if not snap.exists:
        defaults = dict(SERVER_HARDCODED_DEFAULTS)
        ref.set({"defaults": defaults, "updatedAt": now})
        return defaults

    stored = (snap.to_dict() or {}).get("defaults") or {}
    if overwrite_existing:
        defaults = dict(SERVER_HARDCODED_DEFAULTS)
    else:
        defaults = dict(stored)
        for cat, v in SERVER_HARDCODED_DEFAULTS.items():
            if not _is_number(defaults.get(cat)):
                defaults[cat] = v
    ref.set({"defaults": defaults, "updatedAt": now}, merge=True)
    return defaults
