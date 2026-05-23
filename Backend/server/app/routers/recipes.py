from typing import Any, Dict, List

from fastapi import APIRouter, Depends
from google.cloud.firestore_v1 import Query

from app import db
from app.auth import CurrentUser, get_current_user
from app.schemas.recipes import (
    RecipeHistoryItem,
    RecipeHistoryResponse,
    RecipeRecommendRequest,
    RecipeRecommendResponse,
    RecipeSource,
)
from app.services import llm_service

router = APIRouter(prefix="/recipes", tags=["recipes"])


@router.post(
    "/recommend",
    response_model=RecipeRecommendResponse,
    summary="보유 재료 기반 LLM 레시피 추천",
)
def recommend_recipes(
    body: RecipeRecommendRequest,
    user: CurrentUser = Depends(get_current_user),
) -> RecipeRecommendResponse:
    return llm_service.generate_recipe_recommendation(body)


@router.get(
    "/history",
    response_model=RecipeHistoryResponse,
    summary="본인이 본 레시피 이력",
)
def list_recipe_history(
    user: CurrentUser = Depends(get_current_user),
) -> RecipeHistoryResponse:
    docs = (
        db.recipe_history_col(user.uid)
        .order_by("viewedAt", direction=Query.DESCENDING)
        .limit(50)
        .stream()
    )

    items: List[RecipeHistoryItem] = []
    for d in docs:
        data: Dict[str, Any] = d.to_dict() or {}
        source_raw = data.get("source") or RecipeSource.LLM.value
        try:
            source = RecipeSource(source_raw)
        except ValueError:
            source = RecipeSource.LLM

        items.append(
            RecipeHistoryItem(
                id=d.id,
                title=data.get("title") or "",
                time=data.get("time") or "",
                description=data.get("description") or "",
                owned_ingredients=list(data.get("ownedIngredients") or []),
                missing_ingredients=list(data.get("missingIngredients") or []),
                steps=list(data.get("steps") or []),
                source=source,
                viewed_at=data.get("viewedAt") or db.utcnow(),
            )
        )
    return RecipeHistoryResponse(items=items)
