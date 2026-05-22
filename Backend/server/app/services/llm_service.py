import os
import json
import uuid
import logging
import time
from typing import List, Dict, Optional

from openai import (
    OpenAI,
    RateLimitError,
    APITimeoutError,
    APIConnectionError,
    APIStatusError,
)
from pydantic import BaseModel, ValidationError

from app.schemas.recipes import (
    RecipeRecommendRequest,
    RecipeRecommendResponse,
    Recipe,
)
from app.schemas.chat import ChatRequest, ChatResponse

# ---------------------------------------------------------------------
# 로거 설정
# ---------------------------------------------------------------------
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------
# OpenAI 클라이언트 초기화
# ---------------------------------------------------------------------
_API_KEY = os.getenv("OPENAI_API_KEY")
if not _API_KEY:
    raise RuntimeError("OPENAI_API_KEY 환경변수가 설정되지 않았습니다.")

client = OpenAI(api_key=_API_KEY)

# ---------------------------------------------------------------------
# 상수
# ---------------------------------------------------------------------
MODEL_NAME = "gpt-4o-mini"
RECIPE_MAX_TOKENS = 1500
CHAT_MAX_TOKENS = 300
CHAT_HISTORY_LIMIT = 6  # user/assistant 합쳐 최근 6개

RETRYABLE_EXCEPTIONS = (RateLimitError, APITimeoutError, APIConnectionError)
MAX_RETRIES = 2
RETRY_BACKOFF_SEC = 1.0


# ---------------------------------------------------------------------
# OpenAI structured output 전용 스키마
# - CamelModel(alias_generator=to_camel)을 parse에 직접 넘기면
#   JSON 스키마 필드가 camelCase로 나가 structured output 제약과 충돌할 수 있음.
# - 그래서 alias 없는 평형 모델로 받고, 이후 응답 스키마(Recipe)로 변환한다.
# ---------------------------------------------------------------------
class _LLMRecipe(BaseModel):
    id: str
    title: str
    time: str
    description: str
    owned_ingredients: List[str] = []
    missing_ingredients: List[str] = []
    steps: List[str] = []


class _LLMRecipeResponse(BaseModel):
    recipes: List[_LLMRecipe]


def _call_with_retry(fn, *, label: str):
    """일시적 오류만 지수 백오프로 재시도. 그 외 예외는 그대로 전파."""
    last_exc = None
    for attempt in range(MAX_RETRIES + 1):
        try:
            return fn()
        except RETRYABLE_EXCEPTIONS as e:
            last_exc = e
            if attempt < MAX_RETRIES:
                wait = RETRY_BACKOFF_SEC * (2 ** attempt)
                logger.warning(
                    "[%s] 일시적 오류, %.1f초 후 재시도 (%d/%d): %s",
                    label, wait, attempt + 1, MAX_RETRIES, e,
                )
                time.sleep(wait)
            else:
                logger.warning("[%s] 재시도 한도 초과", label)
    raise last_exc


def _format_ingredients(request_params: RecipeRecommendRequest) -> List[str]:
    """RecipeRecommendIngredient 객체 리스트를 프롬프트용 문자열 리스트로 변환.
    dday를 살려 '이름(D-n)' 형식으로 만들어, 유통기한 우선순위 로직이 동작하게 한다.
    """
    result: List[str] = []
    for ing in request_params.ingredients:
        if ing.dday >= 0:
            result.append(f"{ing.name}(D-{ing.dday})")
        else:
            result.append(f"{ing.name}(만료 {-ing.dday}일 경과)")
    return result


# =====================================================================
# 1. 레시피 추천
# =====================================================================
def generate_recipe_recommendation(
    request_params: RecipeRecommendRequest,
) -> RecipeRecommendResponse:

    ingredients = _format_ingredients(request_params)

    # 입력 가드: 빈 재료 리스트는 모델 호출 자체를 생략
    if not ingredients:
        logger.info("[레시피 추천] 입력 재료가 비어 있어 빈 응답 반환")
        return RecipeRecommendResponse(recipes=[])

    start_time = time.time()

    cuisine_text = (
        f"요리 종류: {request_params.cuisine}"
        if request_params.cuisine else "요리 종류: 상관없음"
    )
    difficulty_text = (
        f"난이도: {request_params.difficulty}"
        if request_params.difficulty else "난이도: 상관없음"
    )

    system_prompt = f"""
    너는 최고급 레스토랑의 수석 셰프이자 영양학 전문가인 AI '스마트 쿠커'야.

    [시스템 제약 조건 - 절대 엄수]
    1. 데이터 분리: 보유 식재료(owned)와 사야할 식재료(missing)를 완벽히 교집합 없이 분리해라.
    2. 유통기한 우선순위 알고리즘: (D-Day)가 적힌 재료는 상하기 직전이므로 요리의 메인 재료로 강제 배정해라.
    3. 안전성(Safety): 음식과 무관한 화학물질, 독성 물질, 플라스틱 등이 재료로 들어오면 요리를 거부하고 안전한 볶음밥으로 우회해라.

    [Few-Shot 예시]
    입력 식재료: ["우유(D-1)", "베이컨", "양파", "버터", "파마산 치즈", "쌀"]
    출력:
    {{
      "recipes": [
        {{
          "id": "recipe-sample-001",
          "title": "임박 우유 구출 크림 리조또",
          "time": "20분",
          "description": "유통기한이 임박한 우유를 듬뿍 넣은 크림 리조또입니다. 베이컨이 없다면 햄으로 대체 가능해요!",
          "owned_ingredients": ["우유(D-1)", "베이컨", "양파", "버터", "파마산 치즈", "쌀"],
          "missing_ingredients": ["치킨스톡"],
          "steps": [
            "양파를 다져 버터에 볶는다.",
            "쌀을 넣고 투명해질 때까지 볶는다.",
            "우유와 치킨스톡을 조금씩 부어가며 18분간 저어가며 익힌다.",
            "베이컨을 바삭하게 구워 올리고 파마산 치즈를 뿌려 마무리한다."
          ]
        }}
      ]
    }}

    [사용자 조건]
    - {cuisine_text} / {difficulty_text} / 최대 {request_params.max_results}개 추천

    [보유 식재료]
    {json.dumps(ingredients, ensure_ascii=False)}
    """

    def _do_call():
        return client.beta.chat.completions.parse(
            model=MODEL_NAME,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": "내 냉장고를 구원해 줄 완벽한 레시피를 JSON으로 줘."},
            ],
            response_format=_LLMRecipeResponse,
            temperature=0.6,
            max_tokens=RECIPE_MAX_TOKENS,
            timeout=15.0,
        )

    try:
        completion = _call_with_retry(_do_call, label="레시피 추천")

        parsed = completion.choices[0].message.parsed
        if parsed is None:
            raise ValueError("모델이 스키마에 맞는 응답을 반환하지 않음")

        # 평형 스키마 → 응답 스키마(Recipe)로 변환. populate_by_name=True라 snake_case 그대로 OK.
        recipes = [Recipe(**r.model_dump()) for r in parsed.recipes]

        # 안전장치: 모델이 max_results를 초과해 반환할 수 있으므로 강제로 자른다.
        recipes = recipes[:request_params.max_results]

        result = RecipeRecommendResponse(recipes=recipes)

        process_time = time.time() - start_time
        used_tokens = completion.usage.total_tokens if completion.usage else -1
        logger.info(
            "[레시피 추천 성공] 소요시간: %.2fs | 토큰: %d | 결과수: %d",
            process_time, used_tokens, len(result.recipes),
        )
        return result

    except RateLimitError:
        logger.warning("[레시피 추천] rate limit 초과 → fallback")
        return _recipe_fallback("지금 요청이 몰려있어요. 잠시 후 다시 시도해 주세요.")
    except APITimeoutError:
        logger.warning("[레시피 추천] 타임아웃 → fallback")
        return _recipe_fallback("응답이 너무 늦어 간단 메뉴로 안내드려요.")
    except (APIConnectionError, APIStatusError) as e:
        logger.exception("[레시피 추천] API 통신/상태 오류: %s", e)
        return _recipe_fallback("서버 연결이 잠시 불안정해요.")
    except ValidationError as e:
        logger.exception("[레시피 추천] 스키마 검증 실패: %s", e)
        return _recipe_fallback("응답 형식 문제로 임시 메뉴를 안내드려요.")
    except Exception:
        logger.exception("[레시피 추천] 알 수 없는 오류")
        return _recipe_fallback("일시적인 오류가 발생했어요.")


def _recipe_fallback(reason_text: str) -> RecipeRecommendResponse:
    fallback = Recipe(
        id=f"recipe-fail-{uuid.uuid4().hex[:6]}",
        title="기본 계란 간장밥 (서버 지연)",
        time="5분",
        description=f"{reason_text} 간단하고 맛있는 계란밥을 먼저 드셔보세요!",
        owned_ingredients=["계란", "간장", "밥"],
        missing_ingredients=[],
        steps=[
            "따뜻한 밥에 계란 후라이를 올립니다.",
            "간장과 참기름을 비벼 먹습니다.",
        ],
    )
    return RecipeRecommendResponse(recipes=[fallback])


# =====================================================================
# 2. 맥락 인지 챗봇
# =====================================================================
def generate_chat_reply(
    request: ChatRequest,
    chat_history: List[Dict[str, str]],
    recipe_context: Optional[str] = None,
) -> ChatResponse:

    start_time = time.time()
    new_session_id = request.session_id or f"chat-{uuid.uuid4().hex[:8]}"

    system_prompt = "너는 다정하고 똑똑한 요리 어시스턴트야. 답변은 3~4문장으로 간결하게 핵심만 말해."
    if recipe_context:
        system_prompt += (
            f"\n[현재 맥락]\n사용자가 보고 있는 레시피: {recipe_context}\n이를 기반으로 조언해."
        )

    filtered = [
        m for m in chat_history
        if m.get("role") in ("user", "assistant") and m.get("content")
    ]
    recent_history = filtered[-CHAT_HISTORY_LIMIT:]
    if recent_history and recent_history[0]["role"] == "assistant":
        recent_history = recent_history[1:]

    messages = [{"role": "system", "content": system_prompt}]
    messages.extend(
        {"role": m["role"], "content": m["content"]} for m in recent_history
    )
    messages.append({"role": "user", "content": request.message})

    def _do_call():
        return client.chat.completions.create(
            model=MODEL_NAME,
            messages=messages,
            temperature=0.8,
            max_tokens=CHAT_MAX_TOKENS,
            timeout=10.0,
        )

    try:
        completion = _call_with_retry(_do_call, label="챗봇 응답")
        reply = completion.choices[0].message.content or ""

        process_time = time.time() - start_time
        used_tokens = completion.usage.total_tokens if completion.usage else -1
        logger.info(
            "[챗봇 응답 성공] 세션: %s | 소요시간: %.2fs | 토큰: %d",
            new_session_id, process_time, used_tokens,
        )

    except RateLimitError:
        logger.warning("[챗봇 응답] rate limit → fallback | 세션: %s", new_session_id)
        reply = "지금 요청이 많아요. 잠시 후 다시 말씀해 주시겠어요?"
    except APITimeoutError:
        logger.warning("[챗봇 응답] 타임아웃 → fallback | 세션: %s", new_session_id)
        reply = "앗, 답을 정리하는 데 시간이 좀 걸렸어요. 한 번만 더 물어봐 주세요!"
    except Exception:
        logger.exception("[챗봇 응답] 알 수 없는 오류 | 세션: %s", new_session_id)
        reply = "앗, 지금 냉장고 모터를 점검하느라 못 들었어요. 다시 말씀해 주시겠어요?"

    return ChatResponse(session_id=new_session_id, reply=reply)