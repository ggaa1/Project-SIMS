from fastapi import APIRouter, Depends

from app import db
from app.auth import CurrentUser, get_current_user
from app.schemas.users import UserMeResponse

router = APIRouter(prefix="/users", tags=["users"])


@router.get(
    "/me",
    response_model=UserMeResponse,
    summary="현재 로그인한 사용자 정보 (없으면 첫 호출 시 Firestore에 자동 생성)",
)
def get_me(user: CurrentUser = Depends(get_current_user)) -> UserMeResponse:
    ref = db.users_col().document(user.uid)
    snap = ref.get()
    now = db.utcnow()

    if not snap.exists:
        # Frontend가 이미 만들어둘 수도 있지만, 서버를 먼저 부른 경우 방어용으로 생성
        payload = {
            "email": user.email or "",
            "fridgeIds": [],
            "createdAt": now,
            "updatedAt": now,
        }
        if user.name:
            payload["displayName"] = user.name
        ref.set(payload)
        data = payload
    else:
        data = snap.to_dict() or {}

    return UserMeResponse(
        uid=user.uid,
        email=data.get("email") or user.email or "",
        display_name=data.get("displayName") or user.name,
        photo_url=data.get("photoURL"),
        fridge_ids=list(data.get("fridgeIds") or []),
        created_at=data.get("createdAt") or now,
        updated_at=data.get("updatedAt") or now,
    )
