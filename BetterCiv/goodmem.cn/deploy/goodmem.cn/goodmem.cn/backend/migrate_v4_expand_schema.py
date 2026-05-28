import asyncio
import asyncpg
import os
from dotenv import load_dotenv

async def migrate_schema():
    load_dotenv()
    db_url = os.getenv('DATABASE_URL')
    if not db_url:
        print("DATABASE_URL not found")
        return

    conn = await asyncpg.connect(db_url)
    try:
        print("[*] Upgrading articles table column types...")
        # Increase sizes for fields that might be longer in the LLM-rewritten content
        await conn.execute("""
            ALTER TABLE articles ALTER COLUMN title TYPE VARCHAR(512);
            ALTER TABLE articles ALTER COLUMN subtitle TYPE VARCHAR(512);
            ALTER TABLE articles ALTER COLUMN judgment_tag TYPE VARCHAR(255);
            ALTER TABLE articles ALTER COLUMN keywords TYPE TEXT;
            ALTER TABLE articles ALTER COLUMN drug_type TYPE VARCHAR(255);
            ALTER TABLE articles ALTER COLUMN drug_layer TYPE VARCHAR(255);
            ALTER TABLE articles ALTER COLUMN cluster_id TYPE VARCHAR(10);
            ALTER TABLE articles ALTER COLUMN external_code TYPE VARCHAR(20);
            ALTER TABLE articles ALTER COLUMN legacy_id TYPE VARCHAR(20);
        """)
        print("[+] Schema migration completed successfully.")
    except Exception as e:
        print(f"[!] Migration failed: {e}")
    finally:
        await conn.close()

if __name__ == '__main__':
    asyncio.run(migrate_schema())
