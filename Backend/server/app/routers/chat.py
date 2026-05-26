from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends
from google.cloud.firestore_v1 import Query

from app import db
from app.auth import CurrentUser, get_current_user
from app.schemas.chat import ChatRequest, ChatResponse
from app.services import llm_service

router = APIRouter(tags=["chat"])

# llm_service.CHAT_HISTORY_LIMIT(6) 보다 넉넉히 가져와서 user/assistant 페어 보장
_FETCH_LIMIT = 12


def _load_recipe_context(uid: str, recipe_id: str) -> Optional[str]:
    snap = db.recipe_history_col(uid).document(recipe_id).get()
    if not snap.exists:
        return None
    data: Dict[str, Any] = snap.to_dict() or {}

    parts = [f"제목: {data.get('title') or ''}"]
    if data.get("time"):
        parts.append(f"소요시간: {data['time']}")
    if data.get("description"):
        parts.append(f"설명: {data['description']}")

    owned = data.get("ownedIngredients") or []
    missing = data.get("missingIngredients") or []
    if owned:
        parts.append(f"보유 재료: {', '.join(owned)}")
    if missing:
        parts.append(f"필요 재료: {', '.join(missing)}")

    steps = data.get("steps") or []
    if steps:
        parts.append("조리 순서: " + " / ".join(steps))
    return " | ".join(parts)


def _load_history(uid: str, session_id: str) -> List[Dict[str, str]]:
    docs = (
        db.chat_messages_col(uid, session_id)
        .order_by("createdAt", direction=Query.DESCENDING)
        .limit(_FETCH_LIMIT)
        .stream()
    )

    history: List[Dict[str, str]] = []
    for d in docs:
        data = d.to_dict() or {}
        role = data.get("role")
        text = data.get("text")
        if role in ("user", "assistant") and text:
            history.append({"role": role, "content": text})

    history.reverse()  # 시간순
    return history


def _save_message(uid: str, session_id: str, role: str, text: str) -> None:
    now = db.utcnow()
    db.chat_messages_col(uid, session_id).document().set({
        "role": role,
        "text": text,
        "createdAt": now,
    })
    db.chat_sessions_col(uid).document(session_id).update({"updatedAt": now})


def _ensure_session(
    uid: str, session_id: Optional[str], first_message: str, recipe_id: Optional[str]
) -> tuple[str, bool]:
    """기존 세션 사용 또는 새로 생성. (session_id, is_new) 반환."""
    now = db.utcnow()
    title = first_message[:20] + ("..." if len(first_message) > 20 else "")

    if session_id:
        ref = db.chat_sessions_col(uid).document(session_id)
        if ref.get().exists:
            return session_id, False
        # 클라가 임의 ID 보내면 그 ID로 생성
        payload: Dict[str, Any] = {
            "title": title,
            "createdAt": now,
            "updatedAt": now,
        }
        if recipe_id:
            payload["recipeId"] = recipe_id
        ref.set(payload)
        return session_id, True

    ref = db.chat_sessions_col(uid).document()
    payload = {
        "title": title,
        "createdAt": now,
        "updatedAt": now,
    }
    if recipe_id:
        payload["recipeId"] = recipe_id
    ref.set(payload)
    return ref.id, True


@router.post(
    "/chat",
    response_model=ChatResponse,
    summary="챗봇 단발 응답",
)
def chat(
    body: ChatRequest,
    user: CurrentUser = Depends(get_current_user),
) -> ChatResponse:
    session_id, is_new = _ensure_session(
        user.uid, body.session_id, body.message, body.recipe_id
    )

    # 1) 이전 대화 (현재 user message는 아직 저장 전이라 미포함)
    history = [] if is_new else _load_history(user.uid, session_id)

    # 2) recipe 컨텍스트
    recipe_context = None
    if body.recipe_id:
        recipe_context = _load_recipe_context(user.uid, body.recipe_id)

    # 3) user 메시지 저장
    _save_message(user.uid, session_id, "user", body.message)

    # 4) LLM 호출 (session_id를 박아 llm_service가 새로 발급하지 못하게)
    request_with_session = body.model_copy(update={"session_id": session_id})
    response = llm_service.generate_chat_reply(
        request_with_session, history, recipe_context
    )

    # 5) assistant 응답 저장
    _save_message(user.uid, session_id, "assistant", response.reply)

    return ChatResponse(session_id=session_id, reply=response.reply)
