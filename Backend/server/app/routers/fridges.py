import secrets
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from google.cloud.firestore_v1 import ArrayUnion

from app import db
from app.auth import CurrentUser, get_current_user
from app.schemas.fridges import (
    Fridge,
    FridgeCreate,
    FridgeJoinRequest,
    FridgeJoinResponse,
    FridgeListResponse,
)
from app.schemas.shelf_life import CategoryShelfLifeItem, ShelfLifePatch
from app.services import shelf_life

router = APIRouter(prefix="/fridges", tags=["fridges"])


def _verify_member(fridge_id: str, uid: str) -> Dict[str, Any]:
    """fridge 존재 + 멤버 확인. 통과하면 fridge dict 반환."""
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


# Frontend fridge_repository.dart 와 동일한 알파벳 (I, O, 0, 1 제외).
_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


def _generate_invite_code(length: int = 6) -> str:
    return "".join(secrets.choice(_CODE_ALPHABET) for _ in range(length))


def _unique_invite_code() -> str:
    """다른 fridge와 겹치지 않는 invite code를 발급."""
    for _ in range(5):
        code = _generate_invite_code(6)
        existing = (
            db.fridges_col()
            .where(filter=_eq_filter("inviteCode", code))
            .limit(1)
            .get()
        )
        if not existing:
            return code
    # 정말 운 없는 경우 한 자 더
    return _generate_invite_code(7)


def _eq_filter(field: str, value: Any):
    # google-cloud-firestore의 FieldFilter (>=2.16). 구버전 호환 위해 폴백.
    try:
        from google.cloud.firestore_v1.base_query import FieldFilter
        return FieldFilter(field, "==", value)
    except ImportError:  # pragma: no cover
        return (field, "==", value)


def _fridge_from_snapshot(snap) -> Fridge:
    """Firestore 문서 → Fridge. inviteCode 없으면 생성해서 doc에 업데이트."""
    data: Dict[str, Any] = snap.to_dict() or {}
    invite_code = data.get("inviteCode")
    if not invite_code:
        invite_code = _unique_invite_code()
        snap.reference.update({
            "inviteCode": invite_code,
            "updatedAt": db.utcnow(),
        })
        data["inviteCode"] = invite_code

    return Fridge(
        id=snap.id,
        name=data.get("name") or "내 냉장고",
        owner_uid=data.get("ownerUid") or "",
        member_uids=list(data.get("memberUids") or []),
        invite_code=invite_code,
        created_at=data.get("createdAt") or db.utcnow(),
        updated_at=data.get("updatedAt") or db.utcnow(),
    )


@router.post(
    "",
    response_model=Fridge,
    status_code=status.HTTP_201_CREATED,
    summary="냉장고 생성 (자동으로 초대 코드 발급)",
)
def create_fridge(
    body: FridgeCreate,
    user: CurrentUser = Depends(get_current_user),
) -> Fridge:
    now = db.utcnow()
    ref = db.fridges_col().document()
    invite_code = _unique_invite_code()

    payload: Dict[str, Any] = {
        "name": body.name,
        "ownerUid": user.uid,
        "memberUids": [user.uid],
        "inviteCode": invite_code,
        "createdAt": now,
        "updatedAt": now,
    }
    ref.set(payload)

    # 사용자 문서에 fridgeIds 추가 (없으면 생성)
    user_ref = db.users_col().document(user.uid)
    user_snap = user_ref.get()
    if user_snap.exists:
        user_ref.update({
            "fridgeIds": ArrayUnion([ref.id]),
            "updatedAt": now,
        })
    else:
        user_ref.set({
            "email": user.email or "",
            "displayName": user.name,
            "fridgeIds": [ref.id],
            "createdAt": now,
            "updatedAt": now,
        })

    return Fridge(
        id=ref.id,
        name=body.name,
        owner_uid=user.uid,
        member_uids=[user.uid],
        invite_code=invite_code,
        created_at=now,
        updated_at=now,
    )


@router.get(
    "/me",
    response_model=FridgeListResponse,
    summary="내가 속한 냉장고 목록",
)
def list_my_fridges(
    user: CurrentUser = Depends(get_current_user),
) -> FridgeListResponse:
    user_snap = db.users_col().document(user.uid).get()
    fridge_ids: List[str] = []
    if user_snap.exists:
        fridge_ids = list((user_snap.to_dict() or {}).get("fridgeIds") or [])

    fridges: List[Fridge] = []
    for fid in fridge_ids:
        snap = db.fridges_col().document(fid).get()
        if not snap.exists:
            continue
        fridges.append(_fridge_from_snapshot(snap))

    return FridgeListResponse(fridges=fridges)


@router.post(
    "/join",
    response_model=FridgeJoinResponse,
    summary="초대 코드로 냉장고 합류 (memberUids에 본인 uid 추가)",
)
def join_fridge(
    body: FridgeJoinRequest,
    user: CurrentUser = Depends(get_current_user),
) -> FridgeJoinResponse:
    code = body.invite_code.strip().upper()
    query = (
        db.fridges_col()
        .where(filter=_eq_filter("inviteCode", code))
        .limit(1)
        .get()
    )
    if not query:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="해당 초대 코드의 냉장고를 찾을 수 없습니다.",
        )

    snap = query[0]
    data = snap.to_dict() or {}
    member_uids: List[str] = list(data.get("memberUids") or [])
    now = db.utcnow()

    if user.uid not in member_uids:
        snap.reference.update({
            "memberUids": ArrayUnion([user.uid]),
            "updatedAt": now,
        })
        member_uids.append(user.uid)

    # 사용자 문서에도 fridgeId 추가
    user_ref = db.users_col().document(user.uid)
    user_snap = user_ref.get()
    if user_snap.exists:
        user_ref.update({
            "fridgeIds": ArrayUnion([snap.id]),
            "updatedAt": now,
        })
    else:
        user_ref.set({
            "email": user.email or "",
            "displayName": user.name,
            "fridgeIds": [snap.id],
            "createdAt": now,
            "updatedAt": now,
        })

    fridge = Fridge(
        id=snap.id,
        name=data.get("name") or "내 냉장고",
        owner_uid=data.get("ownerUid") or "",
        member_uids=member_uids,
        invite_code=code,
        created_at=data.get("createdAt") or now,
        updated_at=now,
    )
    return FridgeJoinResponse(fridge=fridge, joined_as=user.uid)


# ─── 카테고리별 표준 유통기한 (expiry-spec-v1.md §5) ──────────────────
@router.get(
    "/{fridge_id}/category-shelf-life",
    response_model=List[CategoryShelfLifeItem],
    summary="카테고리별 표준 보관일수 (전역+냉장고 override 머지, 12종)",
)
def get_category_shelf_life(
    fridge_id: str,
    user: CurrentUser = Depends(get_current_user),
) -> List[CategoryShelfLifeItem]:
    fridge = _verify_member(fridge_id, user.uid)
    return [CategoryShelfLifeItem(**row) for row in shelf_life.merged_list(fridge)]


@router.patch(
    "/{fridge_id}/category-shelf-life",
    response_model=List[CategoryShelfLifeItem],
    summary="냉장고 override 수정 (변경분만, null이면 기본값 복귀)",
)
def patch_category_shelf_life(
    fridge_id: str,
    body: ShelfLifePatch,
    user: CurrentUser = Depends(get_current_user),
) -> List[CategoryShelfLifeItem]:
    fridge = _verify_member(fridge_id, user.uid)

    changes = body.root or {}
    # 현재 override 맵을 read-modify-write (키에 '/'가 있어 field-path 갱신 회피).
    current: Dict[str, int] = dict(fridge.get("categoryShelfLife") or {})
    for cat, val in changes.items():
        if cat not in shelf_life.CATEGORIES:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"허용되지 않은 카테고리: {cat}",
            )
        if val is None:
            current.pop(cat, None)  # 기본값 복귀
            continue
        if not isinstance(val, int) or isinstance(val, bool):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"{cat}: 일수는 정수여야 합니다.",
            )
        if not (shelf_life.MIN_DAYS <= val <= shelf_life.MAX_DAYS):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"{cat}: 일수는 {shelf_life.MIN_DAYS}~{shelf_life.MAX_DAYS} 범위여야 합니다.",
            )
        current[cat] = val

    db.fridges_col().document(fridge_id).update({
        "categoryShelfLife": current,
        "updatedAt": db.utcnow(),
    })
    fridge["categoryShelfLife"] = current
    return [CategoryShelfLifeItem(**row) for row in shelf_life.merged_list(fridge)]
