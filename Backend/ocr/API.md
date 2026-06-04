# OCR API — 인계용 명세

이미지(영수증/실물 사진)를 받아 식재료 항목 리스트로 반환하는 단일 엔드포인트.
내부 구현은 Gemini Vision 1회 호출 + response_schema 강제. 프론트엔드는 응답을
사용자에게 보여주고 수정/확정받은 뒤 server에 영구 저장하는 흐름을 권장합니다.

OpenAPI 인터랙티브 문서: `http://localhost:8081/docs` (uvicorn 실행 중일 때)

---

## 엔드포인트

```
POST /ocr/text
Content-Type: multipart/form-data
```

### 헤더
- 현재: 미인증 (개발용 dummy auth 통과)
- 향후 server 통합 시: Firebase ID Token을 `Authorization: Bearer <token>` 헤더에
  실어서 전달. 현 모듈은 `app.dependency_overrides[get_current_user]` 로 server 측
  실제 의존성을 주입받는 구조.

### 요청 바디 (multipart fields)
| 필드 | 타입 | 필수 | 설명 |
|---|---|---|---|
| `file` | file | ✓ | 처리할 이미지 |

### 허용 content-type
`image/jpeg`, `image/jpg`, `image/png`, `image/webp`, `image/heic`, `image/heif`

### 제한
- 파일 크기: **≤ 10MB** (10 \* 1024 \* 1024 bytes)
- 이미지는 백엔드에서 자동 전처리됨 — EXIF 회전 보정, 1536px 긴변 리사이즈, JPEG 92 재인코딩

---

## 응답

### 200 OK — `OcrTextResponse`

```json
{
  "source_kind": "receipt",
  "items": [
    {"category": "육류", "name": "한우 앞다리", "quantity": "1", "coefficient": 0.8}
  ],
  "model": "gemini-3.1-flash-lite"
}
```

| 필드 | 타입 | 설명 |
|---|---|---|
| `source_kind` | `"receipt"` \| `"object"` | 이미지 분류 결과. UI 분기에 활용. |
| `items` | `Item[]` | 추출된 식재료 항목 리스트. 비어있을 수 있음. |
| `model` | string | 응답 생성에 사용된 Gemini 모델 식별자. 디버깅·감사용 |

### `Item` 객체

| 필드 | 타입 | 설명 |
|---|---|---|
| `category` | enum (12종) | 카테고리. 유통기한 매핑용 proxy. 아래 enum 참조. |
| `name` | string | 한국어 품명. OCR 원문 + 컨텍스트 보정. |
| `quantity` | string | 수량. **digits-only** ("1", "2", "12") 또는 빈 문자열. 단위 suffix 없음. |
| `coefficient` | float | **유통기한 계수.** 카테고리 표준 보관일수에 곱해 만료일을 미세조정(`expireDate = today + round(표준일수 × coefficient)`). 표준보다 오래가는 품목(냉동만두·통조림)은 > 1, 빨리 상하는 품목(생선회)은 < 1, 기본 1.0. 권장 범위 `0.1~10`(server에서 범위 밖은 클램프). 일관성을 위해 **저온(temperature↓) 추론**. server가 만료일 산정 후 폐기하며 DB에 저장하지 않음. 상세: `docs/expiry-spec-v1.md` §4.1 |

### `category` enum
```
"야채", "과일", "육류", "수산물", "유제품", "달걀",
"곡물/면", "조미료/소스", "음료", "냉동식품", "간식/과자", "기타"
```
- LLM이 이 enum 외 카테고리는 출력 불가능 (response_schema로 강제됨)
- "엄밀 분류"가 아닌 "유통기한 매핑 proxy"임을 유념. 예: 스팸이 육류/냉동식품/기타 중 어디로 갈지는 호출마다 흔들릴 수 있음 → frontend UI에서 사용자 수정 워크플로우 권장

---

## 에러 응답

| 상태코드 | 케이스 |
|---|---|
| `400 Bad Request` | 빈 업로드 또는 이미지 디코딩 실패 |
| `413 Request Entity Too Large` | 파일 크기 10MB 초과 |
| `415 Unsupported Media Type` | 허용 외 content-type |
| `502 Bad Gateway` | Gemini API 5xx 응답 또는 schema-conformant 응답 실패 |

에러 응답 형식 (FastAPI 표준):
```json
{"detail": "에러 설명 문자열"}
```

---

## 사용 예시

### curl
```bash
curl -X POST http://localhost:8081/ocr/text \
  -F "file=@receipt.jpg;type=image/jpeg"
```

### Python (httpx)
```python
import httpx
from pathlib import Path

img = Path("receipt.jpg")
with img.open("rb") as f:
    files = {"file": (img.name, f, "image/jpeg")}
    resp = httpx.post("http://localhost:8081/ocr/text", files=files, timeout=60)

resp.raise_for_status()
data = resp.json()
for item in data["items"]:
    print(item["category"], item["name"], item["quantity"])
```

### TypeScript (fetch)
```ts
type OcrItem = {
  category: "야채" | "과일" | "육류" | "수산물" | "유제품" | "달걀"
          | "곡물/면" | "조미료/소스" | "음료" | "냉동식품" | "간식/과자" | "기타";
  name: string;
  quantity: string;     // digits-only or ""
  coefficient: number;  // 유통기한 계수, 기본 1.0 (server에서 만료일 산정에 사용 후 폐기)
};

type OcrTextResponse = {
  source_kind: "receipt" | "object";
  items: OcrItem[];
  model: string;
};

async function ocrText(file: File): Promise<OcrTextResponse> {
  const fd = new FormData();
  fd.append("file", file);
  const r = await fetch("/ocr/text", { method: "POST", body: fd });
  if (!r.ok) throw new Error(`OCR failed: ${r.status} ${await r.text()}`);
  return r.json();
}
```

---

## 응답 예시 (실제 호출 결과)

> ⚠️ 아래 두 스냅샷은 `coefficient` 필드 도입 **이전**에 캡처된 것이라 해당 필드가 빠져 있다.
> 현재 스키마에서는 각 item에 `coefficient`(float, 기본 1.0)가 포함된다(위 `Item` 표 참조).

### 영수증 (`source_kind: "receipt"`)
입력: 마트 영수증 사진 1장
```json
{
  "source_kind": "receipt",
  "items": [
    {"category": "유제품", "name": "노브랜드 굿밀크우유", "quantity": "1"},
    {"category": "기타", "name": "스마트알뜰양복커버", "quantity": "1"},
    {"category": "간식/과자", "name": "농심 포스틱 84g", "quantity": "1"},
    {"category": "곡물/면", "name": "농심 올리브짜파게티", "quantity": "1"},
    {"category": "과일", "name": "산딸기 500g/박스", "quantity": "1"},
    {"category": "기타", "name": "(G)서핑여워터슈NY", "quantity": "1"},
    {"category": "기타", "name": "대여용부직포쇼핑백", "quantity": "1"},
    {"category": "육류", "name": "호주곡물오이스터블", "quantity": "1"},
    {"category": "냉동식품", "name": "오뚜기 콤비네이션피자", "quantity": "1"},
    {"category": "간식/과자", "name": "꼬깔콘허니버터132G", "quantity": "1"},
    {"category": "조미료/소스", "name": "CJ미니드레싱골라담", "quantity": "1"},
    {"category": "조미료/소스", "name": "청정원허브맛솔트", "quantity": "1"},
    {"category": "야채", "name": "태국미니아스파라거스", "quantity": "1"},
    {"category": "간식/과자", "name": "롯데 수박바젤리", "quantity": "2"},
    {"category": "음료", "name": "바리스타 쇼콜라", "quantity": "1"}
  ],
  "model": "gemini-3.1-flash-lite"
}
```

### 실물 사진 (`source_kind: "object"`)
입력: 흰 배경 위 채소·과일 모음 사진 1장
```json
{
  "source_kind": "object",
  "items": [
    {"category": "과일", "name": "바나나", "quantity": "2"},
    {"category": "과일", "name": "사과", "quantity": "1"},
    {"category": "과일", "name": "배", "quantity": "1"},
    {"category": "야채", "name": "파프리카", "quantity": "2"},
    {"category": "야채", "name": "토마토", "quantity": "1"},
    {"category": "야채", "name": "방울토마토", "quantity": "1"},
    {"category": "야채", "name": "쑥갓", "quantity": "1"},
    {"category": "과일", "name": "오렌지", "quantity": "1"}
  ],
  "model": "gemini-3.1-flash-lite"
}
```

---

## 주의사항 / Frontend 워크플로우 가이드

1. **OCR 결과는 항상 사용자 수정 단계를 거칠 것** — LLM 비결정성으로 카테고리·품명·수량 모두 호출마다 흔들림. 같은 영수증을 두 번 불러도 결과가 다를 수 있음. 사용자 confirm/edit 단계가 필수 워크플로우.
2. **`quantity` 는 digits-only 문자열** — DB 저장 시 server 측에서 `float` (예: "2" → 2.0)으로 변환. 사용자가 추후 잔량을 퍼센트(10%, 25% 등)로 차감할 때 fractional 값을 다루기 위함.
3. **OCR 노이즈가 끼어들 수 있음** — 영수증 footer ("감사합니다"), 잘린 단어 ("나드리 180g(트래"), 중복 라인 등이 가끔 items 에 침범. metadata sink 로 대부분 흡수되지만 100%는 아님 — 사용자 삭제 가능한 UI 필요.
4. **빈 items 응답 가능** — Gemini가 항목 추출 실패하거나 사진이 모호하면 빈 리스트. 그 경우 사용자에게 "다시 찍어주세요" 안내 권장.
5. **카테고리는 12종 고정** — 새 카테고리 (예: 통조림) 신설은 `Backend/server/docs/schema-v1.md` 의 enum 과 동기화 필요한 design decision. frontend 단독으로 추가하지 말 것.
6. **`source_kind`** — 영수증/실물 사진 구분. UI 라벨이나 후속 처리(영수증은 일자 기록, 실물은 즉시 냉장고 추가 등)에 활용 가능.

---

## 미구현 / 다음 단계

- Server 통합 — `Backend/server/` FastAPI 앱에 ocr_router 마운트, Firebase 인증 의존성 주입, fridge_id 매핑, DB 영구 저장 (quantity str → float 어댑터)
- 사용자 수정 UI 후처리 후 `POST /ingredients` 같은 server 엔드포인트로 확정 데이터 전송 (server 측 명세 별도)
- 잔량 차감 API (퍼센트 단위 사용 기록) — frontend ↔ server 명세 추후 합의

---

## 부록: 백엔드 동작 메모

- **단일 호출**: 이미지 → Gemini Vision (분류 + OCR + 카테고리 분류 모두 1회 API 호출에서 처리)
- **response_schema 강제**: Pydantic `Item` 모델이 Gemini 호출 시 schema로 들어가서 `category` enum 위반 출력 차단
- **metadata sink**: 영수증의 바코드·합계·매장 정보가 items 로 새지 않도록 Gemini schema에 `metadata: list[str]` 필드를 두고 거기로 흡수. API 응답에는 미포함 (디버깅용)
- **모델 변경**: `Backend/.env` 의 `GEMINI_MODEL` env var 로 조정 (기본 `gemini-3.1-flash-lite`). 정확도 더 필요하면 `gemini-2.5-flash` 등으로 교체 가능
- **로컬 fallback**: `Backend/ocr/localocr/` 에 옛 Mac Mini Ollama + PaddleOCR 버전 스냅샷 보존. `uvicorn ocr.localocr.main:app` 으로 인터넷 끊긴 환경 등에서 동작
