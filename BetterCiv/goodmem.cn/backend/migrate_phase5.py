import asyncio
import asyncpg

async def migrate_db():
    conn = await asyncpg.connect('postgresql://postgres:a29806588-run@localhost:5432/DeepStory')
    try:
        await conn.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS out_trade_no VARCHAR(128)")
        await conn.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS cashback_status VARCHAR(32) DEFAULT 'NONE'")
        # 为总设计师的专用通行证加上测试特�?        await conn.execute("UPDATE users SET out_trade_no = 'TEST_WX_TRADE_NO_123456', cashback_status = 'NONE' WHERE token = 'a29806588'")
        print("�?数据库迁移完成，字段已追加！")
    except Exception as e:
        print(f"�?迁移失败: {e}")
    finally:
        await conn.close()

if __name__ == '__main__':
    asyncio.run(migrate_db())
