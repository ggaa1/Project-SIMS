"""shelf_life 서비스 로직 검증 (firebase/deps 불필요).

가짜 `app.db` 모듈을 sys.modules 에 주입해 Firestore 없이 순수 로직을 검증한다.
실행: Backend/server 에서  python -m tests.test_shelf_life   (또는 python tests/test_shelf_life.py)
"""
from __future__ import annotations

import importlib.util
import os
import sys
import types
from datetime import datetime, timezone


# ── 가짜 Firestore (인메모리) ────────────────────────────────────────
class _FakeSnap:
    def __init__(self, data):
        self._data = data
        self.exists = data is not None

    def to_dict(self):
        return self._data


class _FakeDoc:
    def __init__(self, store, key):
        self.store, self.key = store, key

    def get(self):
        return _FakeSnap(self.store.get(self.key))

    def set(self, data, merge=False):
        if merge and isinstance(self.store.get(self.key), dict):
            self.store[self.key] = {**self.store[self.key], **data}
        else:
            self.store[self.key] = data


class _FakeCol:
    def __init__(self, store):
        self.store = store

    def document(self, key):
        return _FakeDoc(self.store, key)


_STORE: dict = {}


def _make_fake_db() -> types.ModuleType:
    m = types.ModuleType("app.db")
    m.app_config_col = lambda: _FakeCol(_STORE)  # type: ignore[attr-defined]
    m.utcnow = lambda: datetime(2026, 6, 4, 1, 0, tzinfo=timezone.utc)  # 10:00 KST  # type: ignore[attr-defined]
    return m


def _load_shelf_life():
    app_pkg = types.ModuleType("app")
    app_pkg.__path__ = []  # 패키지로 인식
    fake_db = _make_fake_db()
    app_pkg.db = fake_db  # type: ignore[attr-defined]
    sys.modules["app"] = app_pkg
    sys.modules["app.db"] = fake_db

    path = os.path.join(os.path.dirname(__file__), "..", "app", "services", "shelf_life.py")
    spec = importlib.util.spec_from_file_location("app.services.shelf_life", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


sl = _load_shelf_life()

_failures = []


def check(label, got, expected):
    ok = got == expected
    print(f"  [{'PASS' if ok else 'FAIL'}] {label}: got={got!r} expected={expected!r}")
    if not ok:
        _failures.append(label)


def kst_date(dt):
    return dt.astimezone(sl.KST).date().isoformat()


now = datetime(2026, 6, 4, 1, 0, tzinfo=timezone.utc)        # 2026-06-04 10:00 KST
now_edge = datetime(2026, 6, 4, 14, 30, tzinfo=timezone.utc)  # 2026-06-04 23:30 KST

print("── 계수 보정 (sanitize_coefficient) ──")
check("정상 1.5", sl.sanitize_coefficient(1.5), 1.5)
check("음수→1.0", sl.sanitize_coefficient(-5), 1.0)
check("0→1.0", sl.sanitize_coefficient(0), 1.0)
check("None→1.0", sl.sanitize_coefficient(None), 1.0)
check("문자열→1.0", sl.sanitize_coefficient("abc"), 1.0)
check("초과 99→10", sl.sanitize_coefficient(99), 10.0)
check("미만 0.01→0.1", sl.sanitize_coefficient(0.01), 0.1)

print("── 일수 클램프 ──")
check("0→1", sl.clamp_days(0), 1)
check("99999→3650", sl.clamp_days(99999), 3650)

print("── 반올림 (0.5 올림) ──")
check("0.6→1", sl._round_half_up(0.6), 1)
check("2.5→3", sl._round_half_up(2.5), 3)

print("── 전역 기본값 (appConfig 없음 → 하드코딩) ──")
_STORE.clear()
gd = sl.get_global_defaults()
check("12종 완비", len(gd), 12)
check("야채 7", gd["야채"], 7)
check("수산물 2", gd["수산물"], 2)

print("── 전역 기본값 (appConfig 일부만 → 누락은 하드코딩으로 메움) ──")
_STORE.clear()
_STORE["categoryShelfLife"] = {"defaults": {"야채": 5}}
gd2 = sl.get_global_defaults()
check("야채 override 5", gd2["야채"], 5)
check("과일 누락→하드7", gd2["과일"], 7)
check("여전히 12종", len(gd2), 12)

print("── effective (냉장고 override) ──")
_STORE.clear()
fridge = {"categoryShelfLife": {"육류": 5}}
check("육류 override 5", sl.effective_days("육류", fridge), 5)
check("야채 전역 7", sl.effective_days("야채", fridge), 7)
check("미지 카테고리→기타", sl.effective_days("없는카테고리", None), 7)

print("── compute_expire_date (KST 날짜 + round(eff×coef)) ──")
_STORE.clear()
check("야채7 ×1.0 → 6/11", kst_date(sl.compute_expire_date("야채", 1.0, None, now)), "2026-06-11")
check("수산물2 ×0.3 → round0.6=1 → 6/5", kst_date(sl.compute_expire_date("수산물", 0.3, None, now)), "2026-06-05")
check("냉동180 ×10 → 1800일", kst_date(sl.compute_expire_date("냉동식품", 10, None, now)), "2031-05-09")
check("경계 23:30KST 야채7 → 6/11", kst_date(sl.compute_expire_date("야채", 1.0, None, now_edge)), "2026-06-11")
check("override 육류5 ×1 → 6/9", kst_date(sl.compute_expire_date("육류", 1.0, {"categoryShelfLife": {"육류": 5}}, now)), "2026-06-09")

print("── merged_list (isCustom) ──")
_STORE.clear()
ml = sl.merged_list({"categoryShelfLife": {"야채": 5}})
veg = next(r for r in ml if r["category"] == "야채")
fruit = next(r for r in ml if r["category"] == "과일")
check("12종 반환", len(ml), 12)
check("야채 is_custom=True days=5", (veg["is_custom"], veg["days"]), (True, 5))
check("과일 is_custom=False days=7", (fruit["is_custom"], fruit["days"]), (False, 7))

print("── seed (생성/merge/overwrite) ──")
_STORE.clear()
sl.seed_global_defaults()
check("생성 후 12종", len(_STORE["categoryShelfLife"]["defaults"]), 12)
# 운영자가 야채를 99로 바꿔둔 상태에서 merge 시드 → 보존
_STORE["categoryShelfLife"]["defaults"]["야채"] = 99
del _STORE["categoryShelfLife"]["defaults"]["과일"]
sl.seed_global_defaults()
check("merge: 야채 99 보존", _STORE["categoryShelfLife"]["defaults"]["야채"], 99)
check("merge: 과일 누락 복구", _STORE["categoryShelfLife"]["defaults"]["과일"], 7)
sl.seed_global_defaults(overwrite_existing=True)
check("overwrite: 야채 7 복구", _STORE["categoryShelfLife"]["defaults"]["야채"], 7)

print()
if _failures:
    print(f"[FAILED] 실패 {len(_failures)}건: {_failures}")
    sys.exit(1)
print("[OK] 전체 통과")
