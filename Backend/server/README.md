# 냉장고를 부탁해 - Server

Python + FastAPI + **Render.com** 기반 백엔드.
Firebase (Auth/Firestore/FCM) + OpenAI (챗봇·레시피 추천).

- **담당**: 고범창 (서버)
- **Firebase 프로젝트**: `projectsims-9dc71`
- **모노레포 위치**: `Backend/server/`
- **관련 문서**: [Firestore 스키마 v1](docs/schema-v1.md) · [API 명세 v1](docs/api-v1.md)

---

## 1. 폴더 구조

```
Backend/server/
├── app/
│   ├── main.py             # FastAPI 인스턴스 + dotenv + CORS + 라우터 등록
│   ├── auth.py             # Firebase ID 토큰 검증 + cron secret 검증
│   ├── db.py               # Firestore 어댑터 (컬렉션 헬퍼)
│   ├── routers/
│   │   ├── health.py       # GET / , GET /healthz
│   │   ├── dummy.py        # GET /dummy/whoami , POST /dummy/echo
│   │   ├── users.py        # GET /users/me
│   │   ├── fridges.py      # POST /fridges, GET /fridges/me, POST /fridges/join
│   │   ├── ingredients.py  # 식재료 CRUD (+ from-receipt/from-image stub)
│   │   ├── recipes.py      # POST /recipes/recommend, GET /recipes/history
│   │   ├── chat.py         # POST /chat
│   │   ├── fcm.py          # POST /fcm/register
│   │   └── tasks.py        # POST /tasks/check-expiry (cron-job.org)
│   ├── schemas/            # Pydantic 모델 (CamelModel)
│   └── services/
│       └── llm_service.py  # OpenAI 호출 (챗 + 레시피 추천)
├── docs/                   # api-v1.md, schema-v1.md
├── .env.example
├── .dockerignore
├── Dockerfile
├── README.md
├── render.yaml             # Render Blueprint (자동 배포)
└── requirements.txt
```

---

## 2. 로컬 실행 (Windows / cmd 기준)

### 사전 준비 (1회)

#### a) Python 3.12 설치 확인

```cmd
py -3.12 --version
```

설치 안 되어 있으면 https://www.python.org/downloads/ 에서 받아 설치. (3.11 / 3.13도 동작은 함)

#### b) Firebase 서비스 계정 키 발급

1. https://console.firebase.google.com/project/projectsims-9dc71/settings/serviceaccounts/adminsdk
2. **"새 비공개 키 생성"** → JSON 다운로드
3. 다운로드한 파일을 **`Backend/server/service-account.json`** 으로 저장 (이름 정확히)
4. `.gitignore`에 등록되어 있어 커밋될 위험 없음

#### c) `.env` 파일 작성

`Backend/server/.env` 파일 만들고 아래 내용 채우기:

```dotenv
# Firebase Admin SDK 서비스 계정 키 경로
GOOGLE_APPLICATION_CREDENTIALS=./service-account.json

# OpenAI API 키 (챗봇 + 레시피 추천)
# https://platform.openai.com/api-keys
OPENAI_API_KEY=sk-여기에_실제_키

# /tasks/check-expiry 보호용 비밀키 (32자 랜덤)
CRON_SECRET=여기에_랜덤_긴_문자열

# 로컬 테스트: Bearer dev-token 으로 인증 우회
# 배포 환경에서는 절대 1로 두지 말 것
DEV_AUTH_ENABLED=1

# CORS — 모바일 앱만 쓰면 그대로 두기
CORS_ORIGINS=http://localhost:3000,http://localhost:8000
```

`CRON_SECRET` 32자 랜덤 생성 (cmd, venv 활성화 후):

```cmd
python -c "import secrets; print(secrets.token_urlsafe(24))"
```

> ⚠️ `OPENAI_API_KEY` 없으면 `/chat`, `/recipes/recommend` 호출 시 fallback 응답이 나옵니다. 서버는 뜨지만 LLM 기능은 작동 안 함.

### 가상환경 + 의존성 설치

```cmd
cd Backend\server

py -3.12 -m venv venv
venv\Scripts\activate.bat

pip install -r requirements.txt
```

### 서버 실행

```cmd
uvicorn app.main:app --reload --port 8000
```

성공 로그:

```
INFO:     Uvicorn running on http://127.0.0.1:8000 (Press CTRL+C to quit)
INFO:     Application startup complete.
```

`.env`는 `app/main.py:5`의 `load_dotenv()`가 자동으로 읽어줍니다.

### Swagger UI 동작 확인

브라우저 → http://localhost:8000/docs

1. 우상단 **Authorize** 클릭
2. Value 칸에 **`dev-token`** 만 입력 (⚠️ `Bearer` 접두사 붙이면 안 됨 — Swagger가 자동으로 붙임)
3. **Authorize** → **Close**

이제 보호된 엔드포인트들이 `user.uid = "user_1"` 로 동작합니다.

### 통합 시나리오 (한 바퀴 돌려보기)

| 순서 | 엔드포인트 | body |
|---|---|---|
| 1 | `GET /users/me` | — |
| 2 | `POST /fridges` | `{"name":"내 냉장고"}` → inviteCode 응답 |
| 3 | `POST /fridges/{fid}/ingredients` | `{"name":"양파","category":"야채","count":3,"expireDate":"2026-05-26","addedVia":"manual"}` |
| 4 | `GET /fridges/{fid}/ingredients` | 등록한 식재료 목록 |
| 5 | `POST /recipes/recommend` | 위 ingredients 담아 호출 → LLM 응답 |
| 6 | `POST /chat` | `{"message":"오늘 저녁 뭐 먹지?"}` → sessionId 응답 |
| 7 | 같은 sessionId로 `POST /chat` 재호출 | 이전 대화 기억 확인 |

각 호출 후 Firebase 콘솔(Firestore)에서 데이터가 잘 들어가는지 시각적으로도 확인 권장.

---

## 3. 다음 실행 시 (이후)

가상환경 다시 활성화만:

```cmd
cd Backend\server
venv\Scripts\activate.bat
uvicorn app.main:app --reload --port 8000
```

`requirements.txt`가 바뀌었을 때만 `pip install -r requirements.txt` 추가.

---

## 4. Docker로 실행 (선택)

배포 전 컨테이너 동작 검증용.

```cmd
docker build -t naengbu-server:dev .

docker run --rm -p 8080:8080 ^
  -v %cd%/service-account.json:/app/service-account.json:ro ^
  -e GOOGLE_APPLICATION_CREDENTIALS=/app/service-account.json ^
  -e OPENAI_API_KEY=%OPENAI_API_KEY% ^
  -e CRON_SECRET=%CRON_SECRET% ^
  -e DEV_AUTH_ENABLED=1 ^
  naengbu-server:dev
```

→ http://localhost:8080/docs

---

## 5. Render.com 배포

> 카드 등록 불필요. GitHub 로그인만으로 시작 가능.

### Step 1. Blueprint로 서비스 생성

1. https://render.com 접속 → **Sign in with GitHub**
2. 대시보드 → **New +** → **Blueprint**
3. `Project-SIMS` 레포 선택 → Render가 `Backend/server/render.yaml` 자동 인식
4. **Apply** 클릭 → `naengbu-server` 서비스 생성됨

### Step 2. Secret File 업로드

생성된 서비스 → **Environment** 탭 → **Secret Files** → **Add Secret File**

- **Filename**: `service-account.json`
- **Contents**: 로컬 `Backend/server/service-account.json` 전체 내용 복붙
- **Save**

Render가 `/etc/secrets/service-account.json` 경로로 마운트. `render.yaml`에서 이미 그 경로를 `GOOGLE_APPLICATION_CREDENTIALS`로 박아둠.

### Step 3. 환경변수 입력

같은 **Environment** 탭의 **Environment Variables**:

| Key | Value |
|---|---|
| `OPENAI_API_KEY` | 본인 OpenAI 키 |
| `CRON_SECRET` | `.env`의 값 그대로 (또는 새 랜덤) |
| `CORS_ORIGINS` | `http://localhost:3000,http://localhost:8000` |

⚠️ `DEV_AUTH_ENABLED`은 절대 안 넣기. 들어가면 누구나 `dev-token`으로 남의 데이터 접근 가능.

**Save Changes** → 자동 재배포.

### Step 4. 배포 확인

- **Logs** 탭에서 빌드 진행 (5~10분)
- 완료 후 상단의 서비스 URL: `https://naengbu-server.onrender.com` 형식
- 브라우저에서 `https://<URL>/healthz` → `{"status":"ok",...}` 응답 확인
- `/docs` 에서 Swagger 동작 확인 (단, `dev-token` 안 먹힘 — Flutter `getIdToken()` 출력값으로 인증)

### 이후 자동 배포

`render.yaml`의 `autoDeploy: true` 덕분에 **GitHub `main` 브랜치에 push만 하면** Render가 자동으로 재배포.

### ⚠️ 무료 플랜 주의

- **15분 무사용 시 sleep** → 첫 요청 시 30초~1분 콜드스타트
- 시연 5분 전 `curl https://<URL>/healthz` 로 깨워두기
- 750시간/월 무료 (24/7 운영 가능)
- 메모리 512MB / CPU 0.1 vCPU

---

## 6. 환경 변수 정리

| 이름 | 로컬 | Render | 설명 |
|------|------|--------|------|
| `GOOGLE_APPLICATION_CREDENTIALS` | `./service-account.json` | `/etc/secrets/service-account.json` | Firebase Admin SDK 키 |
| `OPENAI_API_KEY` | `sk-...` | `sk-...` | OpenAI API 키 |
| `CRON_SECRET` | 32자 랜덤 | 32자 랜덤 | `/tasks/check-expiry` 보호 헤더 |
| `CORS_ORIGINS` | 선택 | 선택 | 콤마 구분 도메인 |
| `DEV_AUTH_ENABLED` | `1` | ❌ 안 넣음 | `Bearer dev-token` 인증 우회 |
| `PORT` | — | 자동 주입 | Render 컨테이너 포트 |

---

## 7. 트러블슈팅

### `Invalid Firebase ID token: Wrong number of segments`
Swagger Authorize에 `Bearer dev-token` 처럼 **`Bearer` 접두사를 같이 입력**한 경우. 토큰 값(`dev-token`)만 입력해야 함.

### `RuntimeError: OPENAI_API_KEY 환경변수가 설정되지 않았습니다`
`.env`에 키가 없거나, 서버 실행 디렉터리가 `.env`와 다른 곳일 때. `Backend\server` 위치에서 실행하는지 확인.

### `firebase_admin.exceptions.DefaultCredentialsError`
`service-account.json`이 없거나 경로 잘못. `Backend\server\service-account.json` 위치에 정확히 있는지 확인.

### 401 그대로 / dev-token 안 먹힘
`.env`에 `DEV_AUTH_ENABLED=1` 있는지 확인. 없으면 추가 후 서버 재시작.

### `address already in use` (port 8000)
이전 uvicorn이 떠있음. `taskkill /IM python.exe /F` 후 재실행 (다른 Python 프로세스 다 죽으니 주의).
