import asyncio
import asyncpg
import os
from dotenv import load_dotenv

async def check_status():
    load_dotenv('backend/.env')
    db_url = os.getenv('DATABASE_URL')
    if not db_url:
        print("DATABASE_URL not found in backend/.env")
        return

    conn = await asyncpg.connect(db_url)
    try:
        # Count articles
        count = await conn.fetchval("SELECT count(*) FROM articles")
        print(f"Database articles count: {count}")

        # Check a few random ones
        sample = await conn.fetch("SELECT id, external_code, title FROM articles LIMIT 5")
        print("\nSample articles from DB:")
        for s in sample:
            print(f"  [{s['id']}] {s['external_code']} - {s['title']}")
            
    finally:
        await conn.close()

if __name__ == '__main__':
    asyncio.run(check_status())
