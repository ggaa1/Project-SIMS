from typing import Dict, Optional

from pydantic import Field, RootModel

from app.schemas._base import CamelModel


class CategoryShelfLifeItem(CamelModel):
    """머지된 카테고리별 표준 보관일수 1건."""

    category: str = Field(..., examples=["야채"])
    days: int = Field(..., examples=[7])
    is_custom: bool = Field(..., description="이 냉장고가 override 한 값이면 true")


class ShelfLifePatch(RootModel[Dict[str, Optional[int]]]):
    """변경분만 전송: {카테고리: 일수}. null 이면 override 제거(전역 기본값 복귀).

    예: {"야채": 5, "육류": 4, "과일": null}
    """
