from datetime import datetime
from typing import List

from pydantic import Field

from app.schemas._base import CamelModel


class FridgeBase(CamelModel):
    name: str = Field(..., min_length=1, max_length=50, examples=["내 냉장고"])


class FridgeCreate(FridgeBase):
    """냉장고 생성 요청. 생성자는 자동으로 ownerUid + memberUids에 추가됨.
    inviteCode는 서버가 자동 발급 (6자 영문 대문자).
    """

    pass


class Fridge(FridgeBase):
    id: str
    owner_uid: str = Field(..., description="생성자 uid")
    member_uids: List[str] = Field(default_factory=list, description="동거인 uid 목록")
    invite_code: str = Field(
        ...,
        min_length=6,
        max_length=7,
        pattern=r"^[A-HJ-NP-Z2-9]{6,7}$",
        examples=["SZCSYJ"],
        description="동거인 초대용 6~7자 코드 (혼동 문자 I,O,0,1 제외)",
    )
    created_at: datetime
    updated_at: datetime


class FridgeListResponse(CamelModel):
    fridges: List[Fridge]


class FridgeJoinRequest(CamelModel):
    invite_code: str = Field(
        ...,
        min_length=6,
        max_length=7,
        pattern=r"^[A-HJ-NP-Z2-9]{6,7}$",
        examples=["SZCSYJ"],
        description="가입할 냉장고의 초대 코드",
    )


class FridgeJoinResponse(CamelModel):
    fridge: Fridge
    joined_as: str = Field(..., description="합류한 사용자 uid (= 본인 uid)")
