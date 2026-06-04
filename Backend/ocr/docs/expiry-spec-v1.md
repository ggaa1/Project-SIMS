# 카테고리별 표준 유통기한 명세 v1

> 상태: **v1 초안 — 2026-05-30 작성**
> 관련 문서: `Backend/server/docs/schema-v1.md` (Firestore 스키마 v2), `Backend/ocr/API.md`
> 적용 대상: OCR/이미지/수동으로 식재료 추가 시 `expireDate` 자동 산정

## 0. 배경 & 목적

식재료를 추가할 때 사용자가 유통기한을 일일이 입력하는 부담을 줄이기 위해,
**카테고리별 "표준 보관일수"** 를 두고 `expireDate`를 자동 계산한다.

- OCR/영수증/이미지 인식 흐름에서는 유통기한 정보가 없는 경우가 대부분 → 카테고리 기반 기본값이 필수.
- 가정·사용자마다 보관 습관이 다르므로 **냉장고 단위로 값을 덮어쓸 수 있게(override)** 한다.

## 1. 핵심 개념 — "유통기한"이 아니라 "보관일수"

표준 유통기한은 **날짜**가 아니라 **추가일로부터의 일수(shelfLifeDays)** 라는 상대값으로 저장한다.

```
expireDate = (식재료 추가 시각) + shelfLifeDays(category) 일
```

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
effective(category) = fridge.categoryShelfLife[category]   // 냉장고가 덮어썼으면 그 값
                      ?? appConfig.defaults[category]        // 아니면 전역 기본값
```

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

1. 식재료 추가 요청(`IngredientCreate`)에 `expireDate`가 **명시되면 그 값을 그대로 사용**한다(사용자 입력 우선).
2. `expireDate`가 비어 있으면:
   - 해당 냉장고의 `categoryShelfLife` + 전역 `defaults`를 머지해 `effective(category)` 산출.
   - `expireDate = now + effective(category)일`.
3. **이미 추가된 식재료에는 소급 적용하지 않는다** — 설정 변경은 *다음 추가분*부터 반영.

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
- 값은 정수 1~3650 범위(범위 밖 400).
- 기본값으로 되돌리려면 해당 키를 `null`로 보내 맵에서 제거(권장) 또는 별도 DELETE 설계.

## 6. Security Rules 방향성

```
// 전역 기본값: 누구나 읽기, 쓰기는 서버(Admin SDK)만
match /appConfig/{docId} {
  allow read: if request.auth != null;
  allow write: if false;          // 클라이언트 직접 쓰기 차단
}

// 냉장고 override: 기존 fridges 규칙 그대로 적용 (멤버만 read/write)
match /fridges/{fridgeId} {
  allow read, write: if request.auth.uid in resource.data.memberUids;
}
```

> `categoryShelfLife`는 `fridges/{fridgeId}` 문서의 일부이므로 기존 멤버 권한 규칙을 그대로 상속한다.

## 7. 검증 규칙

| 항목 | 규칙 |
|------|------|
| 카테고리 키 | `IngredientCategory` 12종 한글 값만 허용 |
| 일수 값 | 정수, `1 ≤ days ≤ 3650` |
| 누락 카테고리 | 허용(sparse) — 누락분은 전역 기본값으로 머지 |
| 권한 | 냉장고 `memberUids`에 포함된 사용자만 수정 |

## 8. 시드 데이터

배포/초기화 시 `appConfig/categoryShelfLife` 문서 1건을 3번 표의 값으로 생성(upsert).
- 이미 존재하면 덮어쓰지 않거나, 운영자 의도에 따라 갱신.
- 냉장고 문서의 `categoryShelfLife`는 초기에 비어 있음(전부 전역 기본값 사용).

## 9. 미결정 / 향후 검토

- **단위(unit) 연동**: 식재료에 `unit` 필드 도입 시(냉장/냉동 구분 등) 보관일수를 냉장/냉동별로 분리할지.
- **품목별 예외**: 카테고리보다 더 세밀한 "품목명 단위" 표준 유통기한 테이블이 필요해지면 별도 설계.
- **되돌리기 UX**: 개별 카테고리 기본값 복원(`null` PATCH vs DELETE) 방식 확정.

## 10. 변경 이력 (Changelog)

### v1 (2026-05-30)
- 최초 작성. 2계층 구조(전역 `appConfig` + 냉장고 override) 확정.
- 전역 기본값 위치를 **Firestore 문서**(`appConfig/categoryShelfLife`)로 결정.
- 설정 단위를 **냉장고 단위**로 결정(식재료가 냉장고에 종속되어 일관성 확보).
- 12종 표준 기본값 확정(3번 표).
