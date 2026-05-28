import asyncio
import asyncpg
import os
from dotenv import load_dotenv

async def check_schema():
    load_dotenv('backend/.env')
    db_url = os.getenv('DATABASE_URL')
    conn = await asyncpg.connect(db_url)
    try:
        print("Columns in 'articles' table:")
        rows = await conn.fetch("""
            SELECT column_name, data_type, character_maximum_length
            FROM information_schema.columns
            WHERE table_name = 'articles'
        """)
        for r in rows:
            print(f"  {r['column_name']}: {r['data_type']} ({r['character_maximum_length']})")
    finally:
        await conn.close()

if __name__ == '__main__':
    asyncio.run(check_schema())
