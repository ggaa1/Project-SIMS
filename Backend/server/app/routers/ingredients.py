from typing import Any, Dict, List

from fastapi import APIRouter, Depends, HTTPException, status

from app import db
from app.auth import CurrentUser, get_current_user
from app.schemas.ingredients import (
    ImageIngestRequest,
    IngestResponse,
    Ingredient,
    IngredientCreate,
    IngredientUpdate,
    ReceiptIngestRequest,
)

router = APIRouter(tags=["ingredients"])

_NOT_IMPL = HTTPException(
    status_code=status.HTTP_501_NOT_IMPLEMENTED,
    detail="OCR 통합 미구현 (별도 OCR 서비스 호출 예정)",
)


def _verify_member(fridge_id: str, uid: str) -> Dict[str, Any]:
    """fridge 존재 + 사용자가 member 인지 확인. 통과하면 fridge dict 반환."""
    snap = db.fridges_col().document(fridge_id).get()
    if not snap.exists:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Fridge not found",
        )
    data = snap.to_dict() or {}
    if uid not in (data.get("memberUids") or []):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="이 냉장고의 멤버가 아닙니다.",
        )
    return data


def _ingredient_from_snapshot(snap, fridge_id: str) -> Ingredient:
    data: Dict[str, Any] = snap.to_dict() or {}
    return Ingredient(
        id=snap.id,
        fridge_id=fridge_id,
        name=data.get("name") or "",
        category=data.get("category") or "기타",
        emoji=data.get("emoji"),
        count=int(data.get("count") or 1),
        expire_date=data.get("expireDate") or db.utcnow(),
        image_url=data.get("imageURL"),
        added_by=data.get("addedBy") or "",
        added_via=data.get("addedVia") or "manual",
        created_at=data.get("createdAt") or db.utcnow(),
        updated_at=data.get("updatedAt") or db.utcnow(),
    )


@router.get(
    "/fridges/{fridge_id}/ingredients",
    response_model=List[Ingredient],
    summary="냉장고 식재료 목록 (유통기한 오름차순)",
)
def list_ingredients(
    fridge_id: str,
    user: CurrentUser = Depends(get_current_user),
) -> List[Ingredient]:
    _verify_member(fridge_id, user.uid)

    docs = (
        db.ingredients_col(fridge_id)
        .order_by("expireDate")
        .stream()
    )
    return [_ingredient_from_snapshot(d, fridge_id) for d in docs]


@router.post(
    "/fridges/{fridge_id}/ingredients",
    response_model=Ingredient,
    status_code=status.HTTP_201_CREATED,
    summary="식재료 단건 추가 (수동 입력)",
)
def create_ingredient(
    fridge_id: str,
    body: IngredientCreate,
    user: CurrentUser = Depends(get_current_user),
) -> Ingredient:
    _verify_member(fridge_id, user.uid)

    now = db.utcnow()
    ref = db.ingredients_col(fridge_id).document()
    payload: Dict[str, Any] = {
        "name": body.name,
        "category": body.category.value,
        "count": body.count,
        "expireDate": body.expire_date,
        "addedBy": user.uid,
        "addedVia": body.added_via.value,
        "createdAt": now,
        "updatedAt": now,
    }
    if body.emoji is not None:
        payload["emoji"] = body.emoji
    if body.image_url is not None:
        payload["imageURL"] = body.image_url
    ref.set(payload)

    return Ingredient(
        id=ref.id,
        fridge_id=fridge_id,
        name=body.name,
        category=body.category,
        emoji=body.emoji,
        count=body.count,
        expire_date=body.expire_date,
        image_url=body.image_url,
        added_by=user.uid,
        added_via=body.added_via,
        created_at=now,
        updated_at=now,
    )


@router.patch(
    "/fridges/{fridge_id}/ingredients/{ingredient_id}",
    response_model=Ingredient,
    summary="식재료 수정 (수량/유통기한 등)",
)
def update_ingredient(
    fridge_id: str,
    ingredient_id: str,
    body: IngredientUpdate,
    user: CurrentUser = Depends(get_current_user),
) -> Ingredient:
    _verify_member(fridge_id, user.uid)

    ref = db.ingredients_col(fridge_id).document(ingredient_id)
    snap = ref.get()
    if not snap.exists:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Ingredient not found",
        )

    patch: Dict[str, Any] = {"updatedAt": db.utcnow()}
    update_data = body.model_dump(exclude_unset=True)

    # snake_case → camelCase Firestore 필드 이름 매핑
    field_map = {
        "name": "name",
        "category": "category",
        "emoji": "emoji",
        "count": "count",
        "expire_date": "expireDate",
        "image_url": "imageURL",
    }
    for py_field, fs_field in field_map.items():
        if py_field in update_data:
            value = update_data[py_field]
            # Enum 인스턴스는 value로 풀기
            patch[fs_field] = value.value if hasattr(value, "value") else value

    ref.update(patch)
    return _ingredient_from_snapshot(ref.get(), fridge_id)


@router.delete(
    "/fridges/{fridge_id}/ingredients/{ingredient_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="식재료 삭제",
)
def delete_ingredient(
    fridge_id: str,
    ingredient_id: str,
    user: CurrentUser = Depends(get_current_user),
) -> None:
    _verify_member(fridge_id, user.uid)

    ref = db.ingredients_col(fridge_id).document(ingredient_id)
    snap = ref.get()
    if not snap.exists:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Ingredient not found",
        )
    ref.delete()


@router.post(
    "/ingredients/from-receipt",
    response_model=IngestResponse,
    summary="영수증 이미지 → OCR → 식재료 일괄 등록",
)
def ingest_from_receipt(
    body: ReceiptIngestRequest,
    user: CurrentUser = Depends(get_current_user),
):
    # OCR 서비스(별도 8081 포트) 통합 단계에서 구현. 현재는 Frontend가
    # OcrService로 직접 호출 → 사용자 수정 → POST /ingredients 흐름.
    raise _NOT_IMPL


@router.post(
    "/ingredients/from-image",
    response_model=IngestResponse,
    summary="식재료 실물 이미지 → 인식 → 등록",
)
def ingest_from_image(
    body: ImageIngestRequest,
    user: CurrentUser = Depends(get_current_user),
):
    raise _NOT_IMPL
