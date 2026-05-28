import asyncio
import asyncpg
import os
from dotenv import load_dotenv

load_dotenv()

async def main():
    pool = await asyncpg.create_pool(os.getenv("DATABASE_URL"))
    async with pool.acquire() as conn:
        # Check current articles
        rows = await conn.fetch("SELECT id, external_code, title FROM articles")
        print("Current checking:")
        for r in rows:
            print(dict(r))
            
        # Update first 3 rows to have the required external_codes if they don't have it
        codes = ["J4250", "S6310", "S4110"]
        titles = ["彼得原理", "进退维谷", "最后一粒沙�?]
        
        for i, code in enumerate(codes):
            # Check if this code exists
            exists = await conn.fetchrow("SELECT id FROM articles WHERE external_code = $1", code)
            if not exists:
                print(f"Creating mock article for {code}")
                await conn.execute("""
                    INSERT INTO articles (novel_key, title, content_html, external_code, rfi_type)
                    VALUES ('mindbreak', $1, '<h1>Mock Content for ' || $2 || '</h1>', $2, 'water')
                    ON CONFLICT (novel_key, title) DO UPDATE SET external_code = $2;
                """, titles[i], code)

        rows = await conn.fetch("SELECT id, external_code, title FROM articles WHERE external_code IN ('J4250', 'S6310', 'S4110')")
        print("After update:")
        for r in rows:
            print(dict(r))

    await pool.close()

if __name__ == "__main__":
    asyncio.run(main())
