import asyncio
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

import asyncpg
from dotenv import load_dotenv
import os


def database_url_for(db_name: str) -> str:
    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        raise RuntimeError("DATABASE_URL is not set. Export it or load it from .env before running init_db.py.")
    parts = urlsplit(database_url)
    return urlunsplit((parts.scheme, parts.netloc, f"/{db_name}", parts.query, parts.fragment))


async def init_db() -> None:
    load_dotenv()
    DeepStory_url = database_url_for("DeepStory")
    postgres_url = database_url_for("postgres")

    sys_conn = await asyncpg.connect(postgres_url)
    try:
        await sys_conn.execute("CREATE DATABASE DeepStory")
        print("[+] Database DeepStory created.")
    except asyncpg.exceptions.DuplicateDatabaseError:
        print("[*] Database DeepStory already exists.")
    finally:
        await sys_conn.close()

    schema_path = Path(__file__).with_name("schema.sql")
    DeepStory_conn = await asyncpg.connect(DeepStory_url)
    try:
        await DeepStory_conn.execute(schema_path.read_text(encoding="utf-8"))
        print("[+] schema.sql applied.")
    finally:
        await DeepStory_conn.close()


if __name__ == "__main__":
    asyncio.run(init_db())
