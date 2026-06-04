# 🍚 냉장고를 부탁해

> 자취생과 1인 가구를 위한 스마트한 식재료 관리 및 맞춤형 레시피 추천 서비스
> "오늘 뭐 먹지?" 고민 끝! 냉장고 파먹기부터 AI 추천까지 다양한 기능을 제공합니다.

**냉장고를 부탁해**는 냉장고 속 식재료의 유통기한을 효율적으로 관리하고, **OpenAI GPT**와 **Google Gemini AI**를 활용하여 보유한 재료에 딱 맞는 레시피를 추천해주는 Flutter 기반 모바일 애플리케이션입니다. FastAPI 백엔드와 Firebase Cloud Functions를 함께 사용해 강력한 서버 기능을 제공합니다.

---

## 📱 프로젝트 소개

- **프로젝트명**: 냉장고를 부탁해 (my_fridge_app)
- **개발 기간**: 2026.03 ~ 2026.06
- **개발 환경**: Flutter (Dart), Firebase, Python (FastAPI), Node.js
- **Firebase 프로젝트**: `projectsims-9dc71`
- **대상 사용자**: 배달 음식에 지친 자취생, 식재료 관리가 어려운 1인 가구
- **핵심 가치**:
  - **Zero Waste**: 유통기한 임박 알림으로 식재료 낭비 방지
  - **Smart AI**: OpenAI GPT + Gemini Vision 기반 레시피 추천 및 OCR 식재료 인식
  - **Share Fridge**: 동거인과 냉장고를 공유하는 초대 코드 시스템

## 🚀 주요 기능

### 1. 🧊 냉장고 관리 (Refrigerator Management)

<img src="https://github.com/user-attachments/assets/5d535ea5-7927-4166-a9e5-f8fc41d71c21" width="240" alt="식재료 리스트" />

- **식재료 등록/수정/삭제**: 이름, 카테고리, 수량, 유통기한, 사진을 등록해 냉장고 현황을 실시간으로 관리합니다.
- **Firebase 연동**: Firestore를 통한 클라우드 동기화로 여러 기기에서 데이터를 공유합니다.
- **유통기한 D-Day 시각화**: 남은 일수에 따라 색상이 달라지는 D-Day 배지를 제공합니다.
- **유통기한 임박 알림**: 홈 화면에서 7일 이내 만료 재료를 우선 표시하고 FCM 푸시 알림을 제공합니다.
- **식재료 이미지**: Firebase Storage에 업로드된 이미지를 냉장고 아이템에 연결합니다.
- **정렬 및 필터링**: 유통기한 오름차순 정렬 및 이름 키워드 검색이 가능합니다.

### 2. 🤝 냉장고 공유 (Share Fridge)

<img src="https://github.com/user-attachments/assets/288b0654-292a-4f7b-83e2-828a277ccae2" width="240" alt="냉장고 공유" />

- **초대 코드**: 6~7자리 영문 코드(I, O, 0, 1 제외)로 동거인을 냉장고에 초대합니다.
- **다중 냉장고**: 여러 냉장고에 소속될 수 있으며, 홈/식재료 화면에서 냉장고를 전환할 수 있습니다.
- **공동 관리**: `memberUids` 배열로 멤버를 관리하며, 모든 멤버가 식재료를 추가/수정/삭제할 수 있습니다.

### 3. 📷 OCR 식재료 등록 (Gemini Vision OCR)

<img src="https://github.com/user-attachments/assets/549ba405-6ac2-47b1-bed4-2e46da1aba65" width="480" alt="OCR 식재료 인식" />

- **영수증 인식**: 마트 영수증 사진을 찍으면 Gemini Vision이 품목을 자동 추출합니다.
- **실물 사진 인식**: 식재료 사진을 찍으면 보이는 식재료 목록을 자동으로 인식합니다.
- **직접 등록**: 이름, 카테고리, 수량, 유통기한, 사진을 직접 입력해 등록합니다.
- **사용자 확인 워크플로우**: OCR 결과를 사용자가 수정/확정한 뒤 일괄 저장합니다.
- **12종 카테고리**: 야채, 과일, 육류, 수산물, 유제품, 달걀, 곡물/면, 조미료/소스, 음료, 냉동식품, 간식/과자, 기타

### 4. 📖 레시피 추천 (Recipe Recommendation)

<img src="https://github.com/user-attachments/assets/d796033f-9d52-46e6-9107-33bc463f9d71" width="240" alt="레시피 추천" />
<img src="https://github.com/user-attachments/assets/0c4aa52a-9503-483b-ae54-a3f49372f73a" width="240" alt="레시피 상세" />

- **AI 기반 맞춤 추천**: OpenAI GPT-4o-mini를 활용해 보유 식재료와 유통기한 D-Day를 반영한 레시피를 추천합니다.
- **D-Day 우선 알고리즘**: 곧 만료되는 재료를 메인 재료로 강제 배정해 식재료 낭비를 방지합니다.
- **추천 결과 캐싱**: 식재료 구성이 바뀌지 않으면 10분간 캐시를 사용해 API 호출을 최소화합니다.
- **레시피 기록**: 본 레시피를 Firestore에 저장해 기록을 조회할 수 있습니다.
- **상세 정보 제공**: 소요 시간, 보유/부족 재료 목록, 조리 순서를 제공합니다.

### 5. 💬 AI 셰프 챗봇

<img src="https://github.com/user-attachments/assets/c4cce971-a1f5-45ab-b572-4e4811e46b51" width="240" alt="AI 셰프 챗봇" />

- **맥락 인지 대화**: 이전 대화 기록(최대 6개)을 유지해 자연스러운 요리 상담이 가능합니다.
- **레시피 연계**: 특정 레시피를 보면서 챗봇에 질문하면 해당 레시피 정보를 컨텍스트로 활용합니다.
- **세션 관리**: 채팅 세션을 Firestore에 저장해 대화 기록을 보존합니다.

### 6. 🔔 알림 시스템 (Notification)

<img src="https://github.com/user-attachments/assets/2ce24430-1f8a-4352-8c12-66ddd6ab32a5" width="240" alt="알림 화면" />

- **FCM 푸시 알림**: Firebase Cloud Functions 스케줄러가 매일 KST 09:00에 D-3 이내 만료 재료가 있는 사용자에게 알림을 발송합니다.
- **로컬 알림 히스토리**: 받은 알림을 로컬(SharedPreferences)에 저장해 알림 화면에서 확인할 수 있습니다.
- **알림 토글**: 설정 화면에서 알림 활성화/비활성화 시 FCM 토큰을 등록/해제합니다.

### 7. 🔐 사용자 인증 (Authentication)

<img src="https://github.com/user-attachments/assets/78f1d9a1-0712-417d-8b67-872803548ee4" width="240" alt="로그인 화면" />

- **이메일/비밀번호 로그인**: Firebase Authentication 기반 인증 시스템입니다.
- **자동 로그인**: 앱 시작 시 기존 로그인 상태를 유지합니다.
- **회원가입 시 냉장고 자동 생성**: 가입 즉시 개인 냉장고가 만들어집니다.

## 🛠 기술 스택 (Tech Stack)

| 구분 | 내용 |
|---|---|
| **Mobile Framework** | [Flutter](https://flutter.dev/) / [Dart](https://dart.dev/) |
| **State Management** | `setState`, `StatefulWidget` |
| **Backend** | [FastAPI](https://fastapi.tiangolo.com/) (Python 3.11), Render.com 배포 |
| **Serverless** | Firebase Cloud Functions v2 (Node.js 24) |
| **Database** | [Cloud Firestore](https://firebase.google.com/docs/firestore) (실시간 동기화) |
| **Authentication** | [Firebase Authentication](https://firebase.google.com/docs/auth) |
| **Storage** | [Firebase Storage](https://firebase.google.com/docs/storage) (식재료 이미지) |
| **Push Notification** | [Firebase Cloud Messaging (FCM)](https://firebase.google.com/docs/cloud-messaging) |
| **AI/LLM** | [OpenAI GPT-4o-mini](https://openai.com/) (레시피 추천·챗봇), [Google Gemini](https://ai.google.dev/) (OCR Vision) |
| **Flutter Packages** | `cloud_firestore`, `firebase_auth`, `firebase_storage`, `firebase_messaging`, `flutter_local_notifications`, `image_picker`, `shared_preferences` |
| **Backend Packages** | `fastapi`, `firebase-admin`, `openai`, `google-genai`, `Pillow` |

---

## 🏗 프로젝트 구조도

> Flutter + FastAPI(Render) + Firebase + 외부 AI 연동

![시스템 구조도](https://github.com/user-attachments/assets/3334a136-0ddd-4da0-89eb-516baaa208b6)

- **실선**: 동기 통신
- **점선**: Firebase 연동
- **화살표 방향**: 데이터 흐름

## 📂 디렉토리 구조 (Directory Structure)

```
Project-SIMS/
├── Frontend/
│   └── my_fridge_app/          # Flutter 앱
│       └── lib/
│           ├── main.dart               # 앱 진입점 (Firebase 초기화, FCM 설정)
│           ├── firebase_options.dart   # Firebase 환경 설정
│           ├── models/                 # 데이터 모델
│           │   ├── ingredient.dart         # 식재료 모델 (D-Day 계산 포함)
│           │   ├── recipe.dart             # 레시피 / 레시피 기록 모델
│           │   ├── chat_message.dart       # 채팅 메시지 / 세션 모델
│           │   ├── ocr_result.dart         # OCR 결과 모델
│           │   ├── user_profile.dart       # 사용자 / 냉장고 모델
│           │   └── notification_record.dart # 알림 기록 모델
│           ├── repositories/           # Firestore 직접 접근 레이어
│           │   ├── ingredient_repository.dart
│           │   ├── fridge_repository.dart
│           │   ├── user_repository.dart
│           │   ├── recipe_history_repository.dart
│           │   ├── chat_repository.dart
│           │   └── fcm_token_repository.dart
│           ├── services/               # 비즈니스 로직
│           │   ├── ingredient_service.dart   # 식재료 CRUD + Storage 연동
│           │   ├── fridge_service.dart       # 냉장고 선택/공유 로직
│           │   ├── recipe_service.dart       # 레시피 추천 (캐싱 포함)
│           │   ├── chat_service.dart         # 챗봇 API 연동
│           │   ├── ocr_service.dart          # OCR API 연동
│           │   ├── auth_service.dart         # Firebase Auth 래퍼
│           │   ├── fcm_service.dart          # FCM 토큰 관리 + 알림 처리
│           │   ├── storage_service.dart      # Firebase Storage 업로드
│           │   ├── notification_settings_service.dart
│           │   ├── notification_history_service.dart
│           │   └── user_profile_service.dart
│           ├── screens/                # UI 화면
│           │   ├── home_screen.dart          # 홈 (유통기한 임박 + 추천 레시피)
│           │   ├── ocr_screen.dart           # 식재료 등록 (OCR / 직접)
│           │   ├── ingredient_list_screen.dart
│           │   ├── ingredient_detail_screen.dart
│           │   ├── recipe_screen.dart        # 레시피 추천 화면
│           │   ├── recipe_detail_screen.dart
│           │   ├── llm_screen.dart           # AI 셰프 챗봇
│           │   ├── notification_screen.dart
│           │   ├── settings_screen.dart
│           │   ├── share_fridge_screen.dart  # 냉장고 공유
│           │   ├── login_screen.dart
│           │   └── signup_screen.dart
│           ├── widgets/
│           │   └── bottom_nav.dart           # 하단 네비게이션 바
│           └── theme/
│               └── app_colors.dart           # 앱 컬러 팔레트
│
└── Backend/
    ├── server/                 # FastAPI 백엔드 (Render.com 배포)
    │   ├── app/
    │   │   ├── main.py             # FastAPI 앱 + CORS + 라우터 등록
    │   │   ├── auth.py             # Firebase ID 토큰 검증
    │   │   ├── db.py               # Firestore 어댑터
    │   │   ├── routers/            # API 엔드포인트
    │   │   │   ├── health.py           # GET /healthz
    │   │   │   ├── users.py            # GET /users/me
    │   │   │   ├── fridges.py          # POST /fridges, GET /fridges/me, POST /fridges/join
    │   │   │   ├── ingredients.py      # 식재료 CRUD
    │   │   │   ├── recipes.py          # POST /recipes/recommend
    │   │   │   ├── chat.py             # POST /chat
    │   │   │   ├── fcm.py              # POST /fcm/register
    │   │   │   └── tasks.py            # POST /tasks/check-expiry (cron)
    │   │   ├── ocr/                # OCR 모듈 (Gemini Vision)
    │   │   │   ├── router.py
    │   │   │   ├── gemini.py
    │   │   │   ├── service.py
    │   │   │   └── preprocess.py
    │   │   ├── schemas/            # Pydantic 모델 (CamelModel)
    │   │   └── services/
    │   │       └── llm_service.py  # OpenAI 챗봇 + 레시피 추천
    │   ├── docs/
    │   │   ├── api-v1.md           # API 명세
    │   │   └── schema-v1.md        # Firestore 스키마 v2
    │   ├── Dockerfile
    │   ├── render.yaml             # Render Blueprint (자동 배포)
    │   └── requirements.txt
    │
    ├── functions/              # Firebase Cloud Functions (Node.js 24)
    │   ├── index.js                # 유통기한 알림 스케줄러 (매일 KST 09:00)
    │   └── package.json
    │
    └── ocr/                    # 독립 OCR 서버 (개발/테스트용)
        ├── main.py
        ├── router.py
        ├── gemini.py
        ├── service.py
        └── requirements.txt
```

## 📝 개발 현황

- [V] **기본 인프라**: Firebase Auth, Firestore, Storage, FCM 연동 완료
- [V] **회원가입/로그인**: Firebase Authentication 구현 완료
- [V] **냉장고 관리**: CRUD, D-Day 시각화, 이미지 업로드 구현 완료
- [V] **냉장고 공유**: 초대 코드 기반 멤버 초대 시스템 구현 완료
- [V] **OCR 식재료 등록**: Gemini Vision 영수증/실물 사진 인식 구현 완료
- [V] **AI 레시피 추천**: OpenAI GPT-4o-mini 기반 추천 + 추천 캐싱 구현 완료
- [V] **AI 셰프 챗봇**: 멀티턴 대화 + 레시피 컨텍스트 연계 구현 완료
- [V] **알림 시스템**: FCM 로컬/클라우드 알림 + Cloud Functions 스케줄러 구현 완료
- [V] **백엔드 배포**: FastAPI → Render.com Docker 배포 완료

---

## 👥 Contributors

- **Developer**:
  - 기세웅(팀장) (2071045)
  - 고범창 (2171346)
  - 김규섭 (2071288)
  - 김진오 (2071358)
  - 이윤수 (2171120)
