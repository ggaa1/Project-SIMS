FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8080

WORKDIR /app

COPY requirements.txt .
RUN pip install --upgrade pip && pip install -r requirements.txt

# ocr 패키지 그대로 복사 (상대 import 유지)
COPY . ./ocr

EXPOSE 8080

CMD ["sh", "-c", "uvicorn ocr.main:app --host 0.0.0.0 --port ${PORT}"]
