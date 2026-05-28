import asyncio, asyncpg, os
from dotenv import load_dotenv
load_dotenv()
db = os.getenv('DATABASE_URL')

async def fix_jsonb():
    conn = await asyncpg.connect(db)
    try:
        await conn.execute("ALTER TABLE users ALTER COLUMN granted_novels DROP DEFAULT")
        await conn.execute("ALTER TABLE users ALTER COLUMN granted_novels TYPE JSONB USING granted_novels::jsonb")
        default_val = '''[\"mindbreak\"]'''
        await conn.execute(f"ALTER TABLE users ALTER COLUMN granted_novels SET DEFAULT '{default_val}'::jsonb")
        print('[+] granted_novels upgraded to JSONB')
        t = await conn.fetchval(
            "SELECT data_type FROM information_schema.columns "
            "WHERE table_name='users' AND column_name='granted_novels'"
        )
        print('type now:', t)
    except Exception as e:
        print('error:', e)
    finally:
        await conn.close()

asyncio.run(fix_jsonb())
