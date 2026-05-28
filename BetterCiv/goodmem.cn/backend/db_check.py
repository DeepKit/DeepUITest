"""修复测试账户 + 完成 JSONB 迁移"""
import asyncio, asyncpg, os
from dotenv import load_dotenv
load_dotenv()
db = os.getenv('DATABASE_URL')

async def fix():
    conn = await asyncpg.connect(db)

    # 1. 查看现有 users
    rows = await conn.fetch("SELECT token, status, granted_novels FROM users LIMIT 10")
    print("Current users:")
    for r in rows:
        print(f"  token={r['token'][:12]}... status={r['status']}")

    # 2. 插入/恢复测试账户（ON CONFLICT 安全�?    await conn.execute("""
        INSERT INTO users (token, granted_novels, payment_status, out_trade_no, cashback_status, status)
        VALUES ('a29806588', '["mindbreak"]', 'Paid', 'TEST_WX_TRADE_NO_123456', 'NONE', 'Active')
        ON CONFLICT (token) DO UPDATE SET
            status = 'Active',
            cashback_status = 'NONE',
            granted_novels = '["mindbreak"]'
    """)
    print("\n[+] Test user a29806588 inserted/restored")

    # 3. TEXT -> JSONB migration
    col_type = await conn.fetchval(
        "SELECT data_type FROM information_schema.columns "
        "WHERE table_name='users' AND column_name='granted_novels'"
    )
    print(f"granted_novels current type: {col_type}")
    if col_type and col_type.lower() != 'jsonb':
        try:
            await conn.execute(
                "ALTER TABLE users ALTER COLUMN granted_novels TYPE JSONB USING granted_novels::jsonb"
            )
            print("[+] granted_novels upgraded TEXT -> JSONB")
        except Exception as e:
            print(f"[!] JSONB upgrade failed: {e}")
    else:
        print("[-] Already JSONB, skip")

    # 4. Add rfi_type if missing
    await conn.execute("ALTER TABLE articles ADD COLUMN IF NOT EXISTS rfi_type VARCHAR(10)")
    print("[+] rfi_type column ensured")

    # 5. Verify
    u = await conn.fetchrow("SELECT token, status, cashback_status FROM users WHERE token='a29806588'")
    print(f"\nVerify: {u}")

    await conn.close()
    print("\n=== Fix complete ===")

asyncio.run(fix())
