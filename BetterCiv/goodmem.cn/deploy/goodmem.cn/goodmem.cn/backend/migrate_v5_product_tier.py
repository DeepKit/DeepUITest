import os
import asyncio
import asyncpg
from dotenv import load_dotenv

load_dotenv()

async def migrate():
    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        print("DATABASE_URL not found!")
        return
    
    conn = await asyncpg.connect(database_url)
    try:
        print("Adding product_tier column to users table...")
        await conn.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS product_tier VARCHAR(20) DEFAULT 'system'")
        print("Migration complete.")
    finally:
        await conn.close()

if __name__ == "__main__":
    asyncio.run(migrate())
