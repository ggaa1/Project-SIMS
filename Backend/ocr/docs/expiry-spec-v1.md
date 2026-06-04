# 카테고리별 표준 유통기한 명세 v2

> 상태: **v2 — 2026-06-04 갱신** (v1 초안 2026-05-30)
> 관련 문서: `Backend/server/docs/schema-v1.md` (Firestore 스키마 v2), `Backend/ocr/API.md`
> 적용 대상: OCR/이미지/수동으로 식재료 추가 시 `expireDate` 자동 산정

## 0. 배경 & 목적

식재료를 추가할 때 사용자가 유통기한을 일일이 입력하는 부담을 줄이기 위해,
**카테고리별 "표준 보관일수"** 를 두고 `expireDate`를 자동 계산한다.

- OCR/영수증/이미지 인식 흐름에서는 유통기한 정보가 없는 경우가 대부분 → 카테고리 기반 기본값이 필수.
- 가정·사용자마다 보관 습관이 다르므로 **냉장고 단위로 값을 덮어쓸 수 있게(override)** 한다.

## 1. 핵심 개념 — "유통기한"이 아니라 "보관일수"

표준 유통기한은 **날짜**가 아니라 **추가일로부터의 일수(shelfLifeDays)** 라는 상대값으로 저장한다.
여기에 품목 단위의 미세 조정을 위한 **유통기한 계수(coefficient)** 를 곱해 최종 만료일을 산정한다.

```
expireDate = (KST 기준 추가 날짜) + round( effective(category) × coefficient ) 일
```

- **계산 주체: 서버.** OCR/이미지/수동 어느 경로든 만료일 산정은 server의 ingest/create 경로에서 수행한다(§4 참조).
- **날짜 기준: KST(UTC+9)의 캘린더 날짜.** 추가 시각의 *시·분*이 아니라 *KST 날짜*를 기준으로 N일을 더한다(프론트 D-day 표시와 일치). 저장은 Firestore `Timestamp`(UTC)지만 일수 가산은 KST 날짜 경계로 한다.
- `effective(category)`: 카테고리 표준 보관일수(전역 기본값 또는 냉장고 override). §2.3 참조.
- `coefficient`: 품목별 계수. 표준보다 오래가는 식품이면 > 1, 빨리 상하면 < 1. 기본 1.0. §4.1 참조.
- `round`: 반올림(0.5 → 올림). 결과가 0 이하가 되면 1로 클램프.
- 날짜를 직접 저장하지 않으므로 언제 추가하든 항상 올바른 만료일이 계산된다.
- 단위: **정수 일(day)**, 최소 1 ~ 최대 3650(약 10년).

## 2. 데이터 위치 (2계층 구조)

### 2.1 전역 기본값 — `appConfig/categoryShelfLife` (단일 문서)

시스템이 제공하는 기본값. **클라이언트 쓰기 금지(읽기 전용)**, 운영자만 수정.

| 필드 | 타입 | 필수 | 설명 |
|------|------|------|------|
| `defaults` | map\<string, integer\> | ✅ | 카테고리(한글 enum 값) → 보관일수. 12종 전부 포함 |
| `updatedAt` | Timestamp | ✅ | 마지막 갱신 |

```jsonc
// appConfig/categoryShelfLife
{
  "defaults": {
    "야채": 7, "과일": 7, "육류": 3, "수산물": 2,
    "유제품": 14, "달걀": 30, "곡물/면": 180,
    "조미료/소스": 180, "음료": 90, "냉동식품": 180,
    "간식/과자": 120, "기타": 7
  },
  "updatedAt": "<Timestamp>"
}
```

### 2.2 냉장고별 override — `fridges/{fridgeId}` 문서에 필드 추가

냉장고 멤버가 수정. **변경한 카테고리만 sparse하게 저장**한다(전체 12개를 항상 채울 필요 없음).

| 필드 | 타입 | 필수 | 설명 |
|------|------|------|------|
| `categoryShelfLife` | map\<string, integer\> | ❌ | 이 냉장고에서 바꾼 카테고리만. 없으면 전역 기본값을 그대로 사용 |

```jsonc
// fridges/{fridgeId}  (기존 필드 + 아래 1개 추가)
{
  "name": "내 냉장고",
  "ownerUid": "...",
  "memberUids": ["..."],
  "inviteCode": "SZCSYJ",
  "categoryShelfLife": {        // ← 신규. 예: 야채/육류만 커스텀
    "야채": 5,
    "육류": 4
  },
  "createdAt": "<Timestamp>",
  "updatedAt": "<Timestamp>"
}
```

> 별도 서브컬렉션을 만들지 않는 이유: 카테고리가 12개로 고정된 enum이라
> 맵 필드 1개로 충분하며, 냉장고 문서 1회 읽기로 모든 값을 가져올 수 있어 비용/복잡도가 낮다.

### 2.3 적용 규칙 (effective value)

```
effective(category) = fridge.categoryShelfLife[category]   // 냉장고가 덮어썼으면 그 값 (sparse, 결손 가능)
                      ?? appConfig.defaults[category]        // 아니면 전역 기본값 (12종 항상 완비)
                      ?? SERVER_HARDCODED_DEFAULTS[category]  // 최후 방어선 (전역 문서까지 비정상일 때)
```

- **계층별 결손 정책:**
  - 냉장고 override(`fridge.categoryShelfLife`): **sparse — 결손 허용.** 없는 카테고리는 전역 기본값이 받친다.
  - 전역 기본값(`appConfig.defaults`): **12종 전부 완비, 결손 금지.** 시드(§8)·검증으로 보장한다.
  - 서버 상수(`SERVER_HARDCODED_DEFAULTS`): 전역 문서가 누락/손상된 비상 상황에만 쓰는 최후 폴백(§3 표 값과 동일). 평상시엔 도달하지 않는다.
- sparse 저장이므로, 전역 기본값을 나중에 조정하면 **냉장고가 안 바꾼 카테고리는 자동으로 새 기본값을 추종**한다.

## 3. 표준 기본값 (12종)

`appConfig/categoryShelfLife.defaults` 초기 시드 값.

| enum 값 | 기본 보관일수 | 비고 |
|---------|:---:|------|
| `야채` | 7 | |
| `과일` | 7 | |
| `육류` | 3 | 신선식품 — 보수적으로 짧게 |
| `수산물` | 2 | 가장 짧음 |
| `유제품` | 14 | |
| `달걀` | 30 | |
| `곡물/면` | 180 | 장기 보관 |
| `조미료/소스` | 180 | 장기 보관 |
| `음료` | 90 | |
| `냉동식품` | 180 | 장기 보관 |
| `간식/과자` | 120 | |
| `기타` | 7 | catch-all — "애매하면 빨리 확인" 의도의 보수값 |

> 카테고리 12종 정의의 출처는 `schema-v1.md` 2.8. 카테고리 추가/삭제 시 이 표도 함께 갱신.

## 4. `expireDate` 자동 계산 흐름

> **쓰기 경로 원칙:** 모든 영구 저장은 **백엔드 API 경유**로만 한다. 클라이언트가 Firestore에 식재료/override를
> 직접 쓰는 것을 금지한다(§6). 만료일 계산도 server에서 수행한다(클라이언트·OCR 모듈이 아님).

1. 식재료 생성 요청에 `expireDate`가 **명시되면 그 값을 그대로 사용**한다(사용자 입력/확정 우선).
2. `expireDate`가 비어 있으면 server가:
   - 해당 냉장고의 `categoryShelfLife` + 전역 `defaults`(+ 서버 상수)를 머지해 `effective(category)` 산출(§2.3).
   - 품목 계수 `coefficient`(없으면 1.0)를 곱해 `expireDate = KST_today + round(effective(category) × coefficient)일`, `[1, 3650]` 클램프.
3. **이미 추가된 식재료에는 소급 적용하지 않는다** — 설정 변경은 *다음 추가분*부터 반영.
   - 클라이언트는 설정 변경 화면에서 "다음에 추가하는 식재료부터 적용됩니다" 류의 간단한 안내를 노출한다(백엔드는 소급 처리 없음).

### 4.1 품목 계수(coefficient) 산출·소비

카테고리(12종)는 거칠어서 같은 카테고리 안에서도 보관기간 차이가 크다(예: `유제품`의 우유 vs 치즈).
품목명 단위의 별도 테이블을 유지하는 대신, **품목별 계수**로 표준값을 미세 조정한다.

- **산출 주체: Gemini OCR.** 영수증/이미지 인식 시 Gemini가 품목마다 `coefficient`를 함께 추론해 반환한다(OCR 응답 스키마 `Item`에 `coefficient` 필드 포함 — `Backend/ocr/API.md` 참조). 표준보다 오래가는 품목(냉동만두, 통조림)은 > 1, 빨리 상하는 품목(생선회)은 < 1.
- **일관성: 저온 추론.** 계수 추론 시 LLM `temperature`를 낮게 설정해 동일 입력에 가급적 일정한 계수가 나오도록 한다(완전 결정적은 아님 → 아래 검증 가드 유지).
- **소비·폐기: server에서 1회 사용 후 버린다.** server가 ingest/create 경로에서 `coefficient`로 `expireDate`를 계산한 뒤, **계수 자체는 식재료 문서에 저장하지 않는다**(저장되는 건 결과 `expireDate`뿐). 소급 적용을 하지 않으므로 재계산용으로 보관할 필요가 없다.
- **검증 가드(클램프):** 계수가 `0.1 ≤ coefficient ≤ 10` 범위를 벗어나면 해당 경계로 클램프하고, 비정상값(음수/0/null/비숫자)·누락은 1.0으로 본다. **계수 때문에 요청을 거부(400)하지 않는다.** 최종 일수는 §1대로 `[1, 3650]` 클램프.
- **사용자 보정: 최종 유통기한(날짜)을 직접 수정.** 사용자는 OCR 결과 확인 화면에서 계수가 아니라 **계산된 유통기한 날짜 자체**를 고쳐 저장한다. 수정된 날짜는 위 1번(명시된 `expireDate`)으로 취급해 그대로 저장한다. (계수는 노출/편집 대상이 아님)
- 별도 품목명→계수 매핑 테이블은 두지 않는다(미채택).

### 4.2 수동 추가 경로

OCR을 거치지 않는 수동 추가는 다음과 같이 동작한다.

- 사용자가 품목명·카테고리 등을 직접 입력한다(계수 개념 없음, 사실상 `coefficient = 1.0`).
- 카테고리가 정해지면 프론트가 그 카테고리의 **effective(전역 또는 냉장고 지정) 유통기한**을 조회해 만료일을 **자동 입력**한다.
- 사용자는 이 자동 입력된 날짜를 수정할 수 있다. **단, 개별 식재료의 날짜를 고쳐도 냉장고의 `categoryShelfLife` override 설정값 자체는 변하지 않는다**(일회성 식재료 수정과 카테고리 기본값 설정은 분리). 카테고리 기본값을 바꾸려면 §5.2 API를 사용한다.

## 5. API (제안)

> 경로는 기존 `fridges` 라우터 컨벤션을 따른다. 멤버 권한(`memberUids`) 검증 필수.

### 5.1 조회 — 머지된 12종 전체 반환

```
GET /fridges/{fridgeId}/category-shelf-life
```

응답 예:
```jsonc
[
  { "category": "야채", "days": 5,  "isCustom": true  },   // 냉장고가 덮어쓴 값
  { "category": "과일", "days": 7,  "isCustom": false },   // 전역 기본값
  ...  // 항상 12개
]
```

### 5.2 수정 — 변경분만 전송

```
PATCH /fridges/{fridgeId}/category-shelf-life
Content-Type: application/json

{ "야채": 5, "육류": 4 }     // 바꾼 카테고리만
```

- 키는 12종 카테고리 enum 값만 허용(그 외 400).
- 값은 정수 1~3650 범위(범위 밖 400). ※ override의 days는 사람이 직접 넣는 값이라 계수와 달리 클램프가 아닌 **거부(400)**.
- 기본값으로 되돌리려면 해당 키를 `null`로 보내 맵에서 제거한다. (복원 UI/로직은 프론트엔드 책임 — §9)

## 6. Security Rules 방향성

> **원칙(§4):** 식재료·override의 영구 쓰기는 **백엔드 API(Admin SDK) 경유만** 허용한다. Admin SDK는
> Security Rules를 우회하므로, 아래 규칙은 *클라이언트 직접 쓰기*를 막는 데 초점을 둔다.

```
// 전역 기본값: 인증 사용자 읽기, 쓰기는 서버(Admin SDK)만
match /appConfig/{docId} {
  allow read: if request.auth != null;
  allow write: if false;          // 클라이언트 직접 쓰기 차단
}

match /fridges/{fridgeId} {
  // 읽기: 멤버만
  allow read: if request.auth.uid in resource.data.memberUids;

  // 생성: create 시점엔 resource == null 이므로 request.resource 를 본다
  allow create: if request.auth.uid in request.resource.data.memberUids;

  // 갱신: 멤버만, 단 categoryShelfLife 는 클라이언트가 직접 못 바꾼다(서버 API 경유 강제)
  allow update: if request.auth.uid in resource.data.memberUids
                && request.resource.data.categoryShelfLife == resource.data.categoryShelfLife;
}
```

> - `categoryShelfLife` 변경은 §5.2 PATCH(백엔드)를 통해서만 일어난다. 위 `update` 규칙의 동등 비교로
>   클라이언트가 이 필드를 직접 수정하는 경로를 차단하고, 값 검증(§7)은 백엔드가 책임진다.
> - ⚠️ 기존 v1 규칙의 `allow read, write: ... resource.data.memberUids` 는 **문서 생성 시 `resource`가 null**
>   이라 create를 막는 결함이 있었다 → create/update 분리로 수정.

## 7. 검증 규칙

| 항목 | 규칙 |
|------|------|
| 카테고리 키 | `IngredientCategory` 12종 한글 값만 허용(그 외 400) |
| override 일수(days) | 정수, `1 ≤ days ≤ 3650`. **범위 밖이면 거부(400)** (사람이 직접 넣는 값) |
| 품목 계수(coefficient) | 실수. `0.1 ≤ coefficient ≤ 10` **밖이면 경계로 클램프**, 비정상(음수/0/null/비숫자)·누락은 1.0. **계수로 인한 400 없음**(LLM 산출값) |
| 최종 일수 | `effective × coefficient` 결과를 `round` 후 `[1, 3650]` 클램프 |
| 누락 카테고리(override) | 허용(sparse) — 누락분은 전역 기본값으로 머지. 전역 기본값은 12종 완비(결손 금지) |
| 권한 | 냉장고 `memberUids` 멤버만 수정, **백엔드 API 경유**(클라 직접 쓰기 차단, §6) |

## 8. 시드 데이터

배포/초기화 시 `appConfig/categoryShelfLife` 문서 1건을 3번 표의 값으로 생성한다.
- **idempotent 보장:** 문서가 없으면 생성, 있으면 **누락된 카테고리 키만 채운다(merge)**. 운영자가 바꾼 기존 값은 보존(덮어쓰지 않음). → 전역 기본값 12종 완비를 항상 유지(§2.3 결손 금지).
- 운영자가 의도적으로 전역 기본값을 갱신할 때는 §5/별도 운영 도구로 명시적 수정.
- 냉장고 문서의 `categoryShelfLife`는 초기에 비어 있음(전부 전역 기본값 사용).

## 9. 결정 사항 (구 미결정 / 2026-06-04 확정)

| 항목 | 결정 |
|------|------|
| **단위(냉장/냉동) 연동** | **배제.** 프론트 UI·Firestore 스키마 어디에도 냉장/냉동 보관구분이 없음(코드 확인 완료). 카테고리 단일 보관일수 유지. 냉동 보관 차이는 카테고리 `냉동식품` 및 품목 계수로 흡수. |
| **품목별 예외** | **표준 유통기한 × 품목 계수(coefficient)** 방식 채택. 계수는 Gemini OCR이 추론하고 사용자가 확인 화면에서 보정. §4.1 참조. (별도 품목명 테이블 미채택) |
| **전역 기본값 저장 위치** | **Firestore `appConfig/categoryShelfLife` 문서**(§2.1 원안). 운영자가 무배포로 수정, 클라이언트 읽기전용. |
| **개별 카테고리 기본값 복원 UX** | **프론트엔드 책임.** override 값의 삭제/변경 UI·로직은 프론트에서 처리. 백엔드는 PATCH로 받은 값 저장/제거(`null` 키 제거)만 수행(§5.2). |
| **소급 미적용 안내** | **클라이언트단 처리.** 백엔드는 소급 적용 없음(§4-3 유지), 프론트가 안내 노출. |
| **쓰기 경로** | **백엔드 API 경유만.** 클라이언트의 Firestore 직접 쓰기 차단(§6 Security Rules로 `categoryShelfLife` 직접 수정 봉쇄). |
| **계수 계산 주체** | **서버.** OCR은 `coefficient`만 반환, server의 ingest/create 경로에서 `expireDate` 산정 후 계수는 폐기(저장 안 함). §4.1. |
| **계수 검증** | **클램프 통일.** `0.1~10` 밖은 경계로 클램프, 비정상·누락은 1.0, 계수로 인한 400 없음. 최종 일수만 `[1,3650]` 클램프. §7. |
| **폴백 계층** | 전역 기본값 12종 결손 금지 / 냉장고 override는 sparse 결손 허용(전역이 받침) / 서버 하드코딩 상수는 최후 방어선. §2.3. |
| **수동 추가** | 프론트에서 카테고리 선택 시 effective 값 자동 입력·수정 가능. 개별 수정이 카테고리 override 설정값을 바꾸지 않음. §4.2. |
| **날짜 기준** | **KST(UTC+9) 캘린더 날짜**로 일수 가산(프론트 D-day와 일치), 저장은 UTC Timestamp. §1. |
| **사용자 보정** | 계수가 아니라 **최종 유통기한 날짜**를 직접 수정해 저장(§4-1로 취급). §4.1. |

### 향후 검토 (열림)

- 계수 범위/검증 경계값의 운영 중 튜닝(현재 `0.1 ≤ coefficient ≤ 10`).
- Gemini 계수 추론 정확도 모니터링 및 프롬프트 보정(저온 추론 고정).

## 10. 변경 이력 (Changelog)

### v2.1 (2026-06-04)
- **쓰기 경로**를 백엔드 API 경유로 일원화(§4 원칙), §6 Security Rules를 create/update 분리 + `categoryShelfLife` 클라 직접 수정 봉쇄로 개정(v1 규칙의 create 시 `resource==null` 결함 수정).
- **계수 출처**를 OCR 응답 스키마(`Item.coefficient`)로 명시(§4.1, `API.md` 동시 개정), **저온 추론**으로 일관성 확보.
- **계수 계산 주체 = 서버**, 계산 후 계수 **폐기(미저장)** 명문화(§4.1).
- **계수 검증 = 클램프 통일**(범위 밖/비정상은 보정, 400 없음), days는 거부(400)로 구분(§7).
- **폴백 계층** 명문화: 전역 결손 금지 / override sparse / 서버 상수 최후 폴백(§2.3), 시드 merge로 12종 완비 보장(§8).
- **수동 추가 경로**(§4.2) 신설: 카테고리→effective 자동입력·수정, 개별 수정이 override 설정을 바꾸지 않음.
- **날짜 기준 KST(UTC+9)** 명시, round 반올림 규칙 명시(§1).
- **사용자 보정 = 최종 날짜 직접 수정**(계수 비노출)으로 확정(§4.1).
- §5.2의 "별도 DELETE" 잔재 제거(`null` 제거로 단일화).

### v2 (2026-06-04)
- §9 미결정 항목 전부 확정 → "결정 사항"으로 이동.
- **단위(냉장/냉동) 연동 배제** 확정(프론트 UI·Firestore 스키마에 보관구분 없음을 코드로 확인).
- **품목 계수(coefficient)** 도입: 카테고리 표준값 × 계수로 만료일 산정(§1, §4.1). 계수는 Gemini OCR 추론 + 사용자 확인 화면 보정.
- **전역 기본값 저장 위치**를 Firestore `appConfig/categoryShelfLife`로 확정(§2.1 원안 유지).
- **개별 기본값 복원 UX**는 프론트엔드 책임으로 확정.
- **소급 미적용 안내**를 클라이언트단 처리로 명시(§4-3).
- ⚠️ 구현 현황: 본 명세의 자동 산정 로직은 아직 **코드 미구현**(스펙만 존재). 별도 구현 필요.

### v1 (2026-05-30)
- 최초 작성. 2계층 구조(전역 `appConfig` + 냉장고 override) 확정.
- 전역 기본값 위치를 **Firestore 문서**(`appConfig/categoryShelfLife`)로 결정.
- 설정 단위를 **냉장고 단위**로 결정(식재료가 냉장고에 종속되어 일관성 확보).
- 12종 표준 기본값 확정(3번 표).
