"""appConfig/categoryShelfLife 전역 기본값 시드 (expiry-spec-v1.md §8).

실행 (Backend/server 디렉터리에서):
    python -m scripts.seed_category_shelf_life            # idempotent: 누락 키만 채움
    python -m scripts.seed_category_shelf_life --overwrite  # 12종 전부 상수로 갱신

전제: Backend/server/.env 에 Firebase 자격증명 등 환경변수 설정(서버와 동일).
"""
from __future__ import annotations

import argparse

from dotenv import load_dotenv

load_dotenv()

from app.services import shelf_life  # noqa: E402  (load_dotenv 이후 import)


def main() -> None:
    parser = argparse.ArgumentParser(description="categoryShelfLife 전역 기본값 시드")
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="기존 값 보존하지 않고 12종 전부 하드코딩 상수로 덮어쓴다.",
    )
    args = parser.parse_args()

    defaults = shelf_life.seed_global_defaults(overwrite_existing=args.overwrite)
    mode = "overwrite" if args.overwrite else "merge(누락만 채움)"
    print(f"[seed] appConfig/categoryShelfLife 갱신 완료 ({mode})")
    for cat in shelf_life.CATEGORIES:
        print(f"  {cat:>8} : {defaults[cat]}일")


if __name__ == "__main__":
    main()
