import asyncio
import asyncpg

async def run():
    conn = await asyncpg.connect('postgresql://postgres:a29806588-run@localhost:5432/DeepStory')
    with open(r'D:\_Progs\02Business\BetterCiv\goodmem.cn\backend\migrate_v2_508.sql', encoding='utf-8') as f:
        sql = f.read()
    await conn.execute(sql)
    await conn.close()
    print('Migration finished successfully')

asyncio.run(run())
