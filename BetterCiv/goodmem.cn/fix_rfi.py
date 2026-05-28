import asyncio
import asyncpg
import os
from dotenv import load_dotenv

async def fix_rfi_type():
    load_dotenv('backend/.env')
    db_url = os.getenv('DATABASE_URL')
    conn = await asyncpg.connect(db_url)
    try:
        print("[*] Fixing rfi_type column length...")
        await conn.execute("ALTER TABLE articles ALTER COLUMN rfi_type TYPE VARCHAR(20)")
        print("[+] Fixed!")
    finally:
        await conn.close()

if __name__ == '__main__':
    asyncio.run(fix_rfi_type())
