import os

from dotenv import load_dotenv

# routers import 전에 .env 로드 (auth.py / llm_service.py가 import 시점에 환경변수를 읽음)
load_dotenv()

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers import (
    chat,
    dummy,
    fcm,
    fridges,
    health,
    ingredients,
    recipes,
    tasks,
    users,
)
from app.ocr.router import router as ocr_router


app = FastAPI(
    title="냉장고를 부탁해 - Server",
    description="Flutter 앱과 연동되는 FastAPI 백엔드 (Render.com 배포)",
    version="0.1.0",
)


_default_origins = "http://localhost:3000,http://localhost:8000"
_origins = [
    o.strip()
    for o in os.getenv("CORS_ORIGINS", _default_origins).split(",")
    if o.strip()
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


app.include_router(health.router)
app.include_router(dummy.router)
app.include_router(users.router)
app.include_router(fridges.router)
app.include_router(ingredients.router)
app.include_router(recipes.router)
app.include_router(chat.router)
app.include_router(fcm.router)
app.include_router(tasks.router)
app.include_router(ocr_router)
