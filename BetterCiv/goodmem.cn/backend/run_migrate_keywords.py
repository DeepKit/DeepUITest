import asyncio
import asyncpg

async def run():
    conn = await asyncpg.connect('postgresql://postgres:a29806588-run@localhost:5432/DeepStory')
    await conn.execute('ALTER TABLE articles ADD COLUMN IF NOT EXISTS keywords VARCHAR(255);')
    await conn.close()
    print('Keywords column added successfully')

asyncio.run(run())
