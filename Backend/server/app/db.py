"""Firestore 어댑터.

Firebase Admin SDK는 app.auth 에서 이미 초기화됨. 여기서는 client만 받아서
컬렉션 reference를 제공한다.

Frontend (Flutter)의 repositories/* 가 사용하는 컬렉션 경로와 동일하게 맞춰
양쪽이 같은 데이터를 본다.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Optional

from firebase_admin import firestore
from google.cloud.firestore_v1.client import Client
from google.cloud.firestore_v1.collection import CollectionReference

import app.auth  # Firebase Admin 초기화 보장 (side effect import)


_client: Optional[Client] = None


def client() -> Client:
    global _client
    if _client is None:
        _client = firestore.client()
    return _client


# ─── 컬렉션 헬퍼 ────────────────────────────────────────────────────
def users_col() -> CollectionReference:
    return client().collection("users")


def fridges_col() -> CollectionReference:
    return client().collection("fridges")


def ingredients_col(fridge_id: str) -> CollectionReference:
    return fridges_col().document(fridge_id).collection("ingredients")


def recipe_history_col(uid: str) -> CollectionReference:
    return (
        client()
        .collection("recipesHistory")
        .document(uid)
        .collection("items")
    )


def chat_sessions_col(uid: str) -> CollectionReference:
    return client().collection("chats").document(uid).collection("sessions")


def chat_messages_col(uid: str, session_id: str) -> CollectionReference:
    return chat_sessions_col(uid).document(session_id).collection("messages")


def fcm_devices_col(uid: str) -> CollectionReference:
    return client().collection("fcmTokens").document(uid).collection("devices")


# ─── 유틸 ──────────────────────────────────────────────────────────
def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def ensure_aware(dt: Any) -> datetime:
    """Firestore SDK가 반환하는 datetime은 보통 tz-aware이지만 안전망."""
    if isinstance(dt, datetime):
        if dt.tzinfo is None:
            return dt.replace(tzinfo=timezone.utc)
        return dt
    raise TypeError(f"datetime이 아닌 값: {type(dt)}")
