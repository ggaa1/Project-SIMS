from fastapi import APIRouter, Depends

from app import db
from app.auth import CurrentUser, get_current_user
from app.schemas.fcm import FCMRegisterRequest, FCMRegisterResponse

router = APIRouter(prefix="/fcm", tags=["fcm"])


@router.post(
    "/register",
    response_model=FCMRegisterResponse,
    summary="앱 디바이스 토큰 등록 (FCM 푸시용)",
)
def register_device(
    body: FCMRegisterRequest,
    user: CurrentUser = Depends(get_current_user),
) -> FCMRegisterResponse:
    db.fcm_devices_col(user.uid).document(body.device_id).set({
        "token": body.token,
        "platform": body.platform.value,
        "lastSeenAt": db.utcnow(),
    }, merge=True)
    return FCMRegisterResponse(ok=True)
