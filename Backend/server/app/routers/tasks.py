from collections import defaultdict
from datetime import timedelta
from typing import Any, Dict, List

from fastapi import APIRouter, Depends
from firebase_admin import messaging
from google.cloud.firestore_v1 import FieldFilter

from app import db
from app.auth import verify_cron_secret
from app.schemas.tasks import CheckExpiryResponse

router = APIRouter(prefix="/tasks", tags=["tasks"])

# D-3 이내 만료 식재료를 임박으로 본다
_EXPIRY_WITHIN_DAYS = 3


@router.post(
    "/check-expiry",
    response_model=CheckExpiryResponse,
    summary="유통기한 임박 식재료 탐지 → FCM 발송 (cron-job.org가 매일 09:00 KST 호출)",
)
def check_expiry(
    _ok: bool = Depends(verify_cron_secret),
) -> CheckExpiryResponse:
    now = db.utcnow()
    cutoff = now + timedelta(days=_EXPIRY_WITHIN_DAYS)

    # 1) 모든 fridge 의 ingredients 중 expireDate <= cutoff 인 것 수집
    docs = (
        db.client()
        .collection_group("ingredients")
        .where(filter=FieldFilter("expireDate", "<=", cutoff))
        .stream()
    )

    # fridge_id → list of (name, expireDate)
    by_fridge: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    for d in docs:
        fridge_ref = d.reference.parent.parent  # fridges/{fid}
        if fridge_ref is None:
            continue
        data = d.to_dict() or {}
        by_fridge[fridge_ref.id].append({
            "name": data.get("name") or "",
            "expireDate": data.get("expireDate"),
        })

    notified_count = 0
    checked_fridges = 0

    for fridge_id, items in by_fridge.items():
        fridge_snap = db.fridges_col().document(fridge_id).get()
        if not fridge_snap.exists:
            continue
        checked_fridges += 1

        fridge_data = fridge_snap.to_dict() or {}
        fridge_name = fridge_data.get("name") or "냉장고"
        member_uids: List[str] = list(fridge_data.get("memberUids") or [])

        # 2) member들의 FCM 토큰 수집
        tokens: List[str] = []
        for uid in member_uids:
            for dev_doc in db.fcm_devices_col(uid).stream():
                tok = (dev_doc.to_dict() or {}).get("token")
                if tok:
                    tokens.append(tok)

        if not tokens:
            continue

        # 3) 알림 본문
        sample_names = [item["name"] for item in items if item["name"]][:3]
        if len(items) == 1:
            body_text = f"{sample_names[0]}의 유통기한이 임박했어요."
        else:
            preview = ", ".join(sample_names)
            body_text = f"{preview} 외 {len(items) - len(sample_names)}개 임박" \
                if len(items) > len(sample_names) else f"{preview} 임박"

        message = messaging.MulticastMessage(
            tokens=tokens,
            notification=messaging.Notification(
                title=f"[{fridge_name}] 유통기한 임박 알림",
                body=body_text,
            ),
            data={
                "type": "expiry",
                "fridgeId": fridge_id,
                "count": str(len(items)),
            },
        )

        try:
            response = messaging.send_each_for_multicast(message)
            notified_count += response.success_count
        except Exception:
            # 한 냉장고 발송 실패가 다른 곳을 막지 않도록
            continue

    return CheckExpiryResponse(
        ok=True,
        notified_count=notified_count,
        checked_fridges=checked_fridges,
    )
